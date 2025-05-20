package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/kardianos/service"
)

// Configuration struct matching your exact requirements
type Config struct {
	ListenAddress  string `json:"listen_address"`
	ListenPort     int    `json:"listen_port"`
	MaxConnections int    `json:"max_connections"`
	BufferSize     int    `json:"buffer_size"`

	// Desync settings - your exact requirements
	DesyncMethod  string `json:"desync_method"`  // "split"
	SplitPosition int    `json:"split_position"` // 4
	SplitAtHost   bool   `json:"split_at_host"`  // false by default
	DesyncHttp    bool   `json:"desync_http"`    // true
	DesyncHttps   bool   `json:"desync_https"`   // true
	DesyncUdp     bool   `json:"desync_udp"`     // true

	// HTTP modifications
	HostRemoveSpaces bool `json:"host_remove_spaces"` // true
	HostMixedCase    bool `json:"host_mixed_case"`    // additional option
	DomainMixedCase  bool `json:"domain_mixed_case"`  // additional option

	// TLS record splitting
	TlsRecordSplit      bool `json:"tls_record_split"`        // true
	TlsRecordSplitPos   int  `json:"tls_record_split_pos"`    // 0
	TlsRecordSplitAtSni bool `json:"tls_record_split_at_sni"` // true

	// Additional options that might be needed
	FakeTtl    int    `json:"fake_ttl"`
	FakeSni    string `json:"fake_sni"`
	DefaultTtl int    `json:"default_ttl"`
	NoDomain   bool   `json:"no_domain"`
	LogLevel   string `json:"log_level"`
}

// Default configuration with your exact specifications
func defaultConfig() *Config {
	return &Config{
		ListenAddress:       "127.0.0.1",
		ListenPort:          1080,
		MaxConnections:      512,
		BufferSize:          16384,
		DesyncMethod:        "split",
		SplitPosition:       4,
		SplitAtHost:         false,
		DesyncHttp:          true,
		DesyncHttps:         true,
		DesyncUdp:           true,
		HostRemoveSpaces:    true,
		HostMixedCase:       false,
		DomainMixedCase:     false,
		TlsRecordSplit:      true,
		TlsRecordSplitPos:   0,
		TlsRecordSplitAtSni: true,
		FakeTtl:             8,
		FakeSni:             "www.iana.org",
		DefaultTtl:          0,
		NoDomain:            false,
		LogLevel:            "info",
	}
}

// Load configuration from file or create default
func loadConfig() *Config {
	configFile := "yallahdpi-config.json"

	// Try to load existing config
	if data, err := os.ReadFile(configFile); err == nil {
		var config Config
		if json.Unmarshal(data, &config) == nil {
			return &config
		}
	}

	// Create default config
	config := defaultConfig()
	if data, err := json.MarshalIndent(config, "", "  "); err == nil {
		os.WriteFile(configFile, data, 0644)
	}

	return config
}

// YallahDPI Windows Service
type YallahDPIService struct {
	config *Config
	proxy  *ProxyServer
	ctx    context.Context
	cancel context.CancelFunc
	logger service.Logger
}

// Main service program
type program struct {
	service *YallahDPIService
}

func (p *program) Start(s service.Service) error {
	go p.run()
	return nil
}

func (p *program) run() {
	p.service.Start()
}

func (p *program) Stop(s service.Service) error {
	return p.service.Stop()
}

// ProxyServer handles all proxy operations
type ProxyServer struct {
	config    *Config
	listener  net.Listener
	ctx       context.Context
	cancel    context.CancelFunc
	conns     map[net.Conn]bool
	connMutex sync.RWMutex
	logger    service.Logger
}

// Start the YallahDPI service
func (bs *YallahDPIService) Start() error {
	bs.ctx, bs.cancel = context.WithCancel(context.Background())
	bs.config = loadConfig()

	bs.proxy = &ProxyServer{
		config: bs.config,
		ctx:    bs.ctx,
		conns:  make(map[net.Conn]bool),
		logger: bs.logger,
	}

	if bs.logger != nil {
		bs.logger.Infof("Starting YallahDPI service on %s:%d", bs.config.ListenAddress, bs.config.ListenPort)
		bs.logger.Infof("Configuration: Split=%d, SplitAtHost=%v, HTTP=%v, HTTPS=%v, UDP=%v, TLS-Split=%v",
			bs.config.SplitPosition, bs.config.SplitAtHost, bs.config.DesyncHttp, bs.config.DesyncHttps,
			bs.config.DesyncUdp, bs.config.TlsRecordSplit)
	}

	return bs.proxy.Start()
}

// Stop the service
func (bs *YallahDPIService) Stop() error {
	if bs.logger != nil {
		bs.logger.Info("Stopping YallahDPI service...")
	}
	if bs.cancel != nil {
		bs.cancel()
	}
	if bs.proxy != nil {
		return bs.proxy.Stop()
	}
	return nil
}

// Start the proxy server
func (ps *ProxyServer) Start() error {
	address := fmt.Sprintf("%s:%d", ps.config.ListenAddress, ps.config.ListenPort)

	var err error
	ps.listener, err = net.Listen("tcp", address)
	if err != nil {
		return fmt.Errorf("failed to listen on %s: %v", address, err)
	}

	if ps.logger != nil {
		ps.logger.Infof("Proxy server listening on %s", address)
	}

	// Accept connections
	go ps.acceptLoop()

	return nil
}

// Stop the proxy server
func (ps *ProxyServer) Stop() error {
	if ps.cancel != nil {
		ps.cancel()
	}

	if ps.listener != nil {
		ps.listener.Close()
	}

	// Close all active connections
	ps.connMutex.Lock()
	for conn := range ps.conns {
		conn.Close()
	}
	ps.connMutex.Unlock()

	return nil
}

// Accept incoming connections
func (ps *ProxyServer) acceptLoop() {
	for {
		select {
		case <-ps.ctx.Done():
			return
		default:
		}

		conn, err := ps.listener.Accept()
		if err != nil {
			if ps.ctx.Err() != nil {
				return // Context cancelled, normal shutdown
			}
			if ps.logger != nil {
				ps.logger.Errorf("Accept error: %v", err)
			}
			continue
		}

		// Track connection
		ps.connMutex.Lock()
		ps.conns[conn] = true
		ps.connMutex.Unlock()

		// Handle connection in goroutine
		go ps.handleConnection(conn)
	}
}

// Handle a single client connection
func (ps *ProxyServer) handleConnection(clientConn net.Conn) {
	defer func() {
		clientConn.Close()
		ps.connMutex.Lock()
		delete(ps.conns, clientConn)
		ps.connMutex.Unlock()
	}()

	// Set connection timeout
	clientConn.SetReadDeadline(time.Now().Add(30 * time.Second))

	// Read the first request
	reader := bufio.NewReader(clientConn)
	firstBytes := make([]byte, 4096)
	n, err := reader.Read(firstBytes)
	if err != nil {
		return
	}

	request := string(firstBytes[:n])

	// Parse the request
	if strings.HasPrefix(request, "CONNECT ") {
		// HTTPS CONNECT method
		ps.handleHTTPSConnect(clientConn, request, firstBytes[:n])
	} else if strings.HasPrefix(request, "GET ") || strings.HasPrefix(request, "POST ") ||
		strings.HasPrefix(request, "PUT ") || strings.HasPrefix(request, "DELETE ") ||
		strings.HasPrefix(request, "HEAD ") || strings.HasPrefix(request, "OPTIONS ") {
		// HTTP request
		ps.handleHTTPRequest(clientConn, request, firstBytes[:n])
	} else {
		// Unknown protocol or raw data - might be SOCKS5 or direct TLS
		ps.handleRawConnection(clientConn, firstBytes[:n])
	}
}

// Handle HTTPS CONNECT requests
func (ps *ProxyServer) handleHTTPSConnect(clientConn net.Conn, requestLine string, initialData []byte) {
	// Parse CONNECT target
	lines := strings.Split(requestLine, "\r\n")
	if len(lines) == 0 {
		return
	}

	parts := strings.Fields(lines[0])
	if len(parts) < 2 {
		return
	}

	target := parts[1]

	// Connect to target server
	serverConn, err := net.DialTimeout("tcp", target, 10*time.Second)
	if err != nil {
		clientConn.Write([]byte("HTTP/1.1 502 Bad Gateway\r\n\r\n"))
		return
	}
	defer serverConn.Close()

	// Send 200 Connection Established
	clientConn.Write([]byte("HTTP/1.1 200 Connection established\r\n\r\n"))

	// Start bidirectional copying with TLS modification
	var wg sync.WaitGroup
	wg.Add(2)

	// Client to server (potentially modify TLS)
	go func() {
		defer wg.Done()
		ps.copyWithTLSModification(serverConn, clientConn, true)
	}()

	// Server to client (no modification)
	go func() {
		defer wg.Done()
		ps.copyWithTLSModification(clientConn, serverConn, false)
	}()

	wg.Wait()
}

// Handle HTTP requests
func (ps *ProxyServer) handleHTTPRequest(clientConn net.Conn, request string, initialData []byte) {
	lines := strings.Split(request, "\r\n")
	if len(lines) == 0 {
		return
	}

	// Parse first line
	parts := strings.Fields(lines[0])
	if len(parts) < 3 {
		return
	}

	// Extract host
	var host string
	for _, line := range lines[1:] {
		if strings.HasPrefix(strings.ToLower(line), "host:") {
			host = strings.TrimSpace(line[5:])
			break
		}
	}

	if host == "" {
		return
	}

	// Add port if not present
	if !strings.Contains(host, ":") {
		host += ":80"
	}

	// Apply HTTP modifications
	modifiedRequest := ps.modifyHTTPRequest(request)

	// Connect to target server
	serverConn, err := net.DialTimeout("tcp", host, 10*time.Second)
	if err != nil {
		clientConn.Write([]byte("HTTP/1.1 502 Bad Gateway\r\n\r\n"))
		return
	}
	defer serverConn.Close()

	// Send modified request with splitting if configured
	requestBytes := []byte(modifiedRequest)
	if ps.config.DesyncHttp {
		ps.sendWithSplit(serverConn, requestBytes, "HTTP")
	} else {
		serverConn.Write(requestBytes)
	}

	// Copy response back
	io.Copy(clientConn, serverConn)
}

// Handle raw connection (could be SOCKS5 or direct TLS)
func (ps *ProxyServer) handleRawConnection(clientConn net.Conn, initialData []byte) {
	// For now, just close the connection
	// In a full implementation, we'd handle SOCKS5 here
	clientConn.Close()
}

// Modify HTTP request according to configuration
func (ps *ProxyServer) modifyHTTPRequest(request string) string {
	lines := strings.Split(request, "\r\n")

	for i, line := range lines {
		if strings.HasPrefix(strings.ToLower(line), "host:") {
			// Apply modifications
			if ps.config.HostRemoveSpaces {
				// Remove spaces after colon
				lines[i] = regexp.MustCompile(`^(Host:)\s+`).ReplaceAllString(line, "$1")
			}

			if ps.config.HostMixedCase {
				// Mix case of "Host:" header
				lines[i] = strings.Replace(lines[i], "Host:", "hOsT:", 1)
			}

			if ps.config.DomainMixedCase {
				// Mix case of domain name
				colonIdx := strings.Index(lines[i], ":")
				if colonIdx > 0 && colonIdx < len(lines[i])-1 {
					domain := lines[i][colonIdx+1:]
					domain = strings.TrimSpace(domain)
					mixedDomain := ps.mixCase(domain)
					lines[i] = lines[i][:colonIdx+1] + " " + mixedDomain
				}
			}
			break
		}
	}

	return strings.Join(lines, "\r\n")
}

// Mix case of a string
func (ps *ProxyServer) mixCase(s string) string {
	result := make([]byte, len(s))
	for i, c := range []byte(s) {
		if i%2 == 0 {
			result[i] = byte(strings.ToUpper(string(c))[0])
		} else {
			result[i] = byte(strings.ToLower(string(c))[0])
		}
	}
	return string(result)
}

// Copy data with TLS modification
func (ps *ProxyServer) copyWithTLSModification(dst, src net.Conn, isClientToServer bool) {
	buffer := make([]byte, ps.config.BufferSize)

	for {
		n, err := src.Read(buffer)
		if err != nil {
			break
		}

		data := buffer[:n]

		// Apply modifications if needed
		if isClientToServer && ps.config.DesyncHttps {
			if ps.isTLSHandshake(data) && ps.config.TlsRecordSplit {
				ps.sendTLSWithSplit(dst, data)
				continue
			} else if ps.config.DesyncMethod == "split" {
				ps.sendWithSplit(dst, data, "TLS")
				continue
			}
		}

		// Send data as-is
		dst.Write(data)
	}
}

// Check if data is TLS handshake
func (ps *ProxyServer) isTLSHandshake(data []byte) bool {
	// TLS record starts with content type (1 byte) + version (2 bytes) + length (2 bytes)
	if len(data) < 6 {
		return false
	}

	// Check for TLS handshake (0x16) and reasonable version
	contentType := data[0]
	version := uint16(data[1])<<8 | uint16(data[2])

	return contentType == 0x16 && (version == 0x0301 || version == 0x0302 || version == 0x0303 || version == 0x0304)
}

// Send TLS data with record splitting
func (ps *ProxyServer) sendTLSWithSplit(dst net.Conn, data []byte) {
	if len(data) < 6 {
		dst.Write(data)
		return
	}

	splitPos := ps.config.TlsRecordSplitPos

	// If split at SNI, try to find SNI position
	if ps.config.TlsRecordSplitAtSni {
		sniPos := ps.findSNIPosition(data)
		if sniPos > 0 {
			splitPos = sniPos
		}
	}

	// For TLS record fragmentation, we need to split within the first TLS record
	if len(data) >= 5 {
		// Read TLS record header
		recordLength := int(data[3])<<8 | int(data[4])
		recordEnd := 5 + recordLength

		if recordEnd <= len(data) && splitPos < recordLength {
			// Split within the TLS record content
			if splitPos == 0 {
				splitPos = 5 + 1 // Split just after TLS header + 1 byte
			} else {
				splitPos = 5 + splitPos
			}

			if splitPos < recordEnd {
				// Create two TLS records from one
				part1Length := splitPos - 5
				part2Length := recordLength - part1Length

				// First TLS record
				firstRecord := make([]byte, 5+part1Length)
				copy(firstRecord[:5], data[:5])
				firstRecord[3] = byte(part1Length >> 8)
				firstRecord[4] = byte(part1Length & 0xff)
				copy(firstRecord[5:], data[5:splitPos])

				// Second TLS record
				secondRecord := make([]byte, 5+part2Length)
				copy(secondRecord[:5], data[:5])
				secondRecord[3] = byte(part2Length >> 8)
				secondRecord[4] = byte(part2Length & 0xff)
				copy(secondRecord[5:], data[splitPos:recordEnd])

				// Send first record
				dst.Write(firstRecord)

				// Small delay to ensure packet separation
				time.Sleep(1 * time.Millisecond)

				// Send second record
				dst.Write(secondRecord)

				// Send any remaining data
				if recordEnd < len(data) {
					dst.Write(data[recordEnd:])
				}
				return
			}
		}
	}

	// Fallback to simple split
	ps.sendWithSplit(dst, data, "TLS-simple")
}

// Find SNI position in TLS ClientHello
func (ps *ProxyServer) findSNIPosition(data []byte) int {
	// Look for SNI extension in TLS ClientHello
	// This is a simplified search - real implementation would parse TLS properly

	// SNI extension type is 0x0000
	for i := 0; i < len(data)-20; i++ {
		// Look for extension type 0x0000 (server_name)
		if i+4 < len(data) && data[i] == 0x00 && data[i+1] == 0x00 {
			// Found potential SNI extension
			return i
		}
	}

	// If no SNI found, split at a reasonable position
	if len(data) > 100 {
		return 50 // Split roughly in the middle of a typical ClientHello
	}

	return ps.config.TlsRecordSplitPos
}

// Send data with packet splitting
func (ps *ProxyServer) sendWithSplit(dst net.Conn, data []byte, context string) {
	splitPos := ps.config.SplitPosition

	// Adjust split position based on context and configuration
	if ps.config.SplitAtHost && context == "HTTP" {
		// Try to split at Host header position
		hostPos := ps.findHostPosition(data)
		if hostPos > 0 {
			splitPos = hostPos
		}
	}

	if splitPos > 0 && splitPos < len(data) {
		// Send first part
		dst.Write(data[:splitPos])

		// Small delay to ensure packet separation
		time.Sleep(1 * time.Millisecond)

		// Send remaining part
		dst.Write(data[splitPos:])
	} else {
		dst.Write(data)
	}
}

// Find Host header position in HTTP request
func (ps *ProxyServer) findHostPosition(data []byte) int {
	dataStr := string(data)
	hostIdx := strings.Index(strings.ToLower(dataStr), "host:")
	if hostIdx > 0 {
		return hostIdx
	}
	return 0
}

func main() {
	// Service configuration
	svcConfig := &service.Config{
		Name:        "YallahDPIGo",
		DisplayName: "YallahDPI Go Service",
		Description: "DPI bypass service with packet desynchronization techniques",
		Option: map[string]interface{}{
			"DelayedAutoStart":       false,
			"OnFailure":              "restart",
			"OnFailureDelayDuration": "5s",
			"OnFailureResetPeriod":   10,
		},
	}

	// Create service instance
	yallahdpiService := &YallahDPIService{}
	prg := &program{service: yallahdpiService}

	s, err := service.New(prg, svcConfig)
	if err != nil {
		log.Fatal(err)
	}

	// Set up logger
	logger, err := s.Logger(nil)
	if err != nil {
		log.Fatal(err)
	}
	yallahdpiService.logger = logger

	// Handle command line arguments
	if len(os.Args) > 1 {
		// Redirect stdout and stderr to null
		if runtime.GOOS == "windows" {
			nullFile, _ := os.OpenFile("NUL", os.O_WRONLY, 0)
			os.Stdout = nullFile
			os.Stderr = nullFile
		}
		switch os.Args[1] {
		case "install":
			err = s.Install()
			if err != nil {
				fmt.Printf("Failed to install service: %v\n", err)
			} else {
				fmt.Println("Service installed successfully")
			}
			return
		case "uninstall":
			err = s.Uninstall()
			if err != nil {
				fmt.Printf("Failed to uninstall service: %v\n", err)
			} else {
				fmt.Println("Service uninstalled successfully")
			}
			return
		case "start":
			err = s.Start()
			if err != nil {
				fmt.Printf("Failed to start service: %v\n", err)
			} else {
				fmt.Println("Service started successfully")
			}
			return
		case "stop":
			err = s.Stop()
			if err != nil {
				fmt.Printf("Failed to stop service: %v\n", err)
			} else {
				fmt.Println("Service stopped successfully")
			}
			return
		case "restart":
			err = s.Restart()
			if err != nil {
				fmt.Printf("Failed to restart service: %v\n", err)
			} else {
				fmt.Println("Service restarted successfully")
			}
			return
		case "console":
			// Run in console mode for testing
			fmt.Println("Starting YallahDPI service in console mode...")
			fmt.Println("Press Ctrl+C to stop")
			yallahdpiService.Start()
			select {} // Block forever
		}
	}

	// Run as service
	err = s.Run()
	if err != nil {
		logger.Error(err)
	}
}
