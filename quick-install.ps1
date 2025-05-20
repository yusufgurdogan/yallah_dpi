# YallahDPI Quick Installer - Works with pre-compiled binary or existing Go
# Usage: iwr -useb https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/quick-install.ps1 | iex

Write-Host "YallahDPI Quick Installer" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

# Check admin privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Administrator privileges required!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Create temp directory
$tempDir = "$env:TEMP\yallahdpi-quick-install"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir | Out-Null

# Create install directory
$installDir = "$env:ProgramFiles\YallahDPI"

# Stop existing service if running
Write-Host "Checking for existing service..." -ForegroundColor Yellow
$service = Get-Service -Name YallahDPIGo -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "Stopping existing service..." -ForegroundColor Yellow
    Stop-Service -Name YallahDPIGo -Force -ErrorAction SilentlyContinue
    sc.exe delete YallahDPIGo 2>$null
    Start-Sleep -Seconds 2
}

# Check if we're currently inside the directory we're trying to delete
# If so, change to a different directory first
if ($PWD.Path -like "$installDir*") {
    Write-Host "Changing directory to avoid removal conflicts..." -ForegroundColor Yellow
    Set-Location -Path $env:TEMP
}

# Now we can safely remove the directory
if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
New-Item -ItemType Directory -Path $installDir | Out-Null

try {
    # Download the pre-compiled binary if available
    $binaryUrl = "https://github.com/yusufgurdogan/yallah_dpi/raw/main/yallahdpi-go.exe"
    $binaryPath = "$installDir\yallahdpi-go.exe"
    $binaryFound = $false

    Write-Host "Attempting to download pre-compiled binary..." -ForegroundColor Green
    try {
        Invoke-WebRequest -Uri $binaryUrl -OutFile $binaryPath -ErrorAction Stop
        $binaryFound = $true
        Write-Host "Pre-compiled binary downloaded successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Pre-compiled binary not available, checking for local Go installation..." -ForegroundColor Yellow
        
        # See if Go is already installed (but don't install it)
        $goInstalled = $null -ne (Get-Command "go" -ErrorAction SilentlyContinue)
        
        if ($goInstalled) {
            Write-Host "Go is installed, building from source..." -ForegroundColor Green
            
            # Download source files
            $sourceFiles = @(
                @{url="https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/main.go"; file="main.go"},
                @{url="https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/go.mod"; file="go.mod"},
                @{url="https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/go.sum"; file="go.sum"}
            )
            
            foreach ($item in $sourceFiles) {
                Write-Host "Downloading $($item.file)..." -ForegroundColor Green
                Invoke-WebRequest -Uri $item.url -OutFile "$tempDir\$($item.file)" -ErrorAction Stop
            }
            
            # Build the executable
            Write-Host "Building YallahDPI executable..." -ForegroundColor Green
            Set-Location $tempDir
            go build -o $binaryPath main.go
            
            if (Test-Path $binaryPath) {
                $binaryFound = $true
                Write-Host "YallahDPI built successfully!" -ForegroundColor Green
            } else {
                throw "Failed to build executable!"
            }
        } else {
            Write-Host "Go is not installed and pre-compiled binary not available." -ForegroundColor Red
            Write-Host "Please either:" -ForegroundColor Yellow
            Write-Host "1. Install Go (https://golang.org/dl/)" -ForegroundColor Yellow
            Write-Host "2. Or compile the binary on another machine and place it in the repository" -ForegroundColor Yellow
            throw "Cannot proceed without binary or Go"
        }
    }
    
    # Check if we have a binary now
    if (-not $binaryFound) {
        throw "No binary available and couldn't build from source."
    }
    
    # Download config
    Write-Host "Downloading configuration..." -ForegroundColor Green
    try {
        $configUrl = "https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/yallahdpi-config.json"
        Invoke-WebRequest -Uri $configUrl -OutFile "$installDir\yallahdpi-config.json" -ErrorAction Stop
    } catch {
        # Create default config if download fails
        Write-Host "Creating default configuration..." -ForegroundColor Yellow
        $defaultConfig = @{
            listen_address = "127.0.0.1"
            listen_port = 1080
            max_connections = 1024
            buffer_size = 16384
            desync_method = "split"
            split_position = 4
            split_at_host = $false
            desync_http = $true
            desync_https = $true
            desync_udp = $true
            host_remove_spaces = $true
            host_mixed_case = $false
            domain_mixed_case = $false
            tls_record_split = $true
            tls_record_split_pos = 0
            tls_record_split_at_sni = $true
            fake_ttl = 8
            fake_sni = "www.iana.org"
            default_ttl = 0
            no_domain = $false
            log_level = "info"
        }
        $defaultConfig | ConvertTo-Json -Depth 10 | Out-File "$installDir\yallahdpi-config.json" -Encoding UTF8
    }
    
    # Install and start service
    Set-Location $installDir
    
    # Stop existing service if running
    Write-Host "Checking for existing service..." -ForegroundColor Yellow
    $service = Get-Service -Name YallahDPIGo -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Stopping existing service..." -ForegroundColor Yellow
        Stop-Service -Name YallahDPIGo -Force -ErrorAction SilentlyContinue
        & "$installDir\yallahdpi-go.exe" stop 2>$null
        & "$installDir\yallahdpi-go.exe" uninstall 2>$null
        Start-Sleep -Seconds 2
    }
    
    # Install and configure service
    Write-Host "Installing service..." -ForegroundColor Green
    & "$installDir\yallahdpi-go.exe" install
    if ($LASTEXITCODE -ne 0) {
        throw "Service installation failed with code: $LASTEXITCODE"
    }
    
    Write-Host "Configuring service..." -ForegroundColor Green
    sc.exe config YallahDPIGo start= auto | Out-Null
    sc.exe failure YallahDPIGo reset= 0 actions= restart/5000/restart/5000/restart/5000 | Out-Null
    
    # Start service
    Write-Host "Starting service..." -ForegroundColor Green
    & "$installDir\yallahdpi-go.exe" start
    Start-Sleep -Seconds 3
    
    # Configure global proxy
    Write-Host "Setting up global proxy..." -ForegroundColor Green
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "http=127.0.0.1:1080;https=127.0.0.1:1080" /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride /t REG_SZ /d "localhost;127.*;10.*;172.16.*-172.31.*;192.168.*;<local>" /f | Out-Null
    netsh.exe winhttp set proxy proxy-server="127.0.0.1:1080" bypass-list="localhost;127.*;192.168.*" | Out-Null
    
    # Configure Windows Firewall
    Write-Host "Configuring Windows Firewall..." -ForegroundColor Green
    Remove-NetFirewallRule -DisplayName "YallahDPI Go*" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "YallahDPI Go - Inbound" -Direction Inbound -Protocol TCP -LocalPort 1080 -Action Allow -Profile Domain,Private | Out-Null
    New-NetFirewallRule -DisplayName "YallahDPI Go - Outbound" -Direction Outbound -Program "$installDir\yallahdpi-go.exe" -Action Allow -Profile Domain,Private | Out-Null
    
    # Verify installation
    Write-Host "Verifying installation..." -ForegroundColor Green
    $service = Get-Service -Name YallahDPIGo -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Host "YallahDPI is running and ready!" -ForegroundColor Green
        Write-Host "DPI bypass is now active for all applications" -ForegroundColor Green
        Write-Host "Service will auto-start on boot" -ForegroundColor Green
        
        # Test connection
        Write-Host "Testing connection..." -ForegroundColor Yellow
        try {
            $testResult = Invoke-WebRequest -Uri "http://httpbin.org/ip" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            Write-Host "Connection test: SUCCESS" -ForegroundColor Green
        } catch {
            Write-Host "Connection test failed (Error: $($_.Exception.Message)), but service is running" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Service is not running. Check logs." -ForegroundColor Red
    }
    
    # Create status check script
    Write-Host "Creating status check script..." -ForegroundColor Green
    $statusScript = @"
# YallahDPI Status Check
Write-Host "YallahDPI Status:" -ForegroundColor Cyan
Get-Service YallahDPIGo | Format-Table -AutoSize
netsh.exe winhttp show proxy
"@
    $statusScript | Out-File -FilePath "$installDir\check-status.ps1" -Encoding UTF8
    
    # Create uninstaller script
    Write-Host "Creating uninstaller script..." -ForegroundColor Green
    $uninstallScript = @"
# YallahDPI Uninstaller
Write-Host "YallahDPI Uninstaller" -ForegroundColor Red
Write-Host "================" -ForegroundColor Red

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Administrator privileges required!" -ForegroundColor Red
    exit 1
}

# Reset proxy settings
Write-Host "Resetting proxy settings..." -ForegroundColor Yellow
reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f | Out-Null
reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /f 2>$null | Out-Null
netsh.exe winhttp reset proxy | Out-Null

# Remove firewall rules
Write-Host "Removing firewall rules..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "YallahDPI Go*" -ErrorAction SilentlyContinue | Out-Null

# Stop and uninstall service
Write-Host "Stopping service..." -ForegroundColor Yellow
Stop-Service -Name YallahDPIGo -Force -ErrorAction SilentlyContinue
& "$installDir\yallahdpi-go.exe" stop 2>$null
& "$installDir\yallahdpi-go.exe" uninstall 2>$null
sc.exe delete YallahDPIGo 2>$null | Out-Null

# Check if we're in the install directory and change if needed
if (\$PWD.Path -like "\$installDir*") {
    Set-Location -Path \$env:TEMP
}

# Remove installation folder
Write-Host "Removing program files..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Remove-Item -Path "\$installDir" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "YallahDPI has been uninstalled." -ForegroundColor Green
"@
    $uninstallScript | Out-File -FilePath "$installDir\uninstall.ps1" -Encoding UTF8
    Copy-Item "$installDir\uninstall.ps1" "$installDir\uninstall-yallahdpi.ps1" -Force
    
} catch {
    Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    # Cleanup
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
}

Write-Host "`nYallahDPI installed successfully!" -ForegroundColor Green
Write-Host "`nManagement Commands:" -ForegroundColor Cyan
Write-Host "  Get-Service YallahDPIGo                      (Check status)" -ForegroundColor White
Write-Host "  $installDir\check-status.ps1              (Detailed status)" -ForegroundColor White
Write-Host "  $installDir\uninstall.ps1                 (Uninstall)" -ForegroundColor White
Write-Host "  $installDir\yallahdpi-go.exe stop/start      (Control service)" -ForegroundColor White