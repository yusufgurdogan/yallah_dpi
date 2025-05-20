# YallahDPI Go Service Installation Script
# Run as Administrator

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Start,
    [switch]$Stop,
    [switch]$Status,
    [switch]$Console
)

# Configuration
$ServiceName = "YallahDPIGo"
$BinaryName = "yallahdpi-go.exe"
$CurrentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinaryPath = Join-Path $CurrentDir $BinaryName

# Colors for output
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Error { Write-Host $args -ForegroundColor Red }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Info { Write-Host $args -ForegroundColor Cyan }

# Check if running as Administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check if binary exists
function Test-Binary {
    if (!(Test-Path $BinaryPath)) {
        Write-Error "Binary not found: $BinaryPath"
        Write-Info "Please run build.bat first to compile the service"
        return $false
    }
    return $true
}

# Get service status
function Get-ServiceStatus {
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        return $service.Status
    }
    catch {
        return "NotInstalled"
    }
}

# Install service
function Install-YallahDPIService {
    Write-Info "Installing YallahDPI Go Service..."
    
    if (!(Test-Binary)) { return }
    
    $status = Get-ServiceStatus
    if ($status -ne "NotInstalled") {
        Write-Warning "Service is already installed (Status: $status)"
        Write-Info "Uninstall first if you want to reinstall"
        return
    }
    
    try {
        & $BinaryPath install
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Service installed successfully!"
            
            # Configure service for automatic restart on failure
            sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/5000
            
            # Set service to start automatically
            Set-Service -Name $ServiceName -StartupType Automatic
            
            Write-Success "Service configured for automatic startup and restart on failure"
        }
        else {
            Write-Error "Installation failed with exit code: $LASTEXITCODE"
        }
    }
    catch {
        Write-Error "Installation error: $($_.Exception.Message)"
    }
}

# Uninstall service
function Uninstall-YallahDPIService {
    Write-Info "Uninstalling YallahDPI Go Service..."
    
    if (!(Test-Binary)) { return }
    
    $status = Get-ServiceStatus
    if ($status -eq "NotInstalled") {
        Write-Warning "Service is not installed"
        return
    }
    
    # Stop service if running
    if ($status -eq "Running") {
        Write-Info "Stopping service first..."
        Stop-YallahDPIService
        Start-Sleep -Seconds 3
    }
    
    try {
        & $BinaryPath uninstall
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Service uninstalled successfully!"
        }
        else {
            Write-Error "Uninstallation failed with exit code: $LASTEXITCODE"
        }
    }
    catch {
        Write-Error "Uninstallation error: $($_.Exception.Message)"
    }
}

# Start service
function Start-YallahDPIService {
    Write-Info "Starting YallahDPI Go Service..."
    
    $status = Get-ServiceStatus
    if ($status -eq "NotInstalled") {
        Write-Error "Service is not installed. Install it first."
        return
    }
    
    if ($status -eq "Running") {
        Write-Warning "Service is already running"
        return
    }
    
    try {
        Start-Service -Name $ServiceName
        Start-Sleep -Seconds 2
        $newStatus = Get-ServiceStatus
        if ($newStatus -eq "Running") {
            Write-Success "Service started successfully!"
            Show-ServiceInfo
        }
        else {
            Write-Error "Failed to start service (Status: $newStatus)"
        }
    }
    catch {
        Write-Error "Start error: $($_.Exception.Message)"
    }
}

# Stop service
function Stop-YallahDPIService {
    Write-Info "Stopping YallahDPI Go Service..."
    
    $status = Get-ServiceStatus
    if ($status -eq "NotInstalled") {
        Write-Error "Service is not installed"
        return
    }
    
    if ($status -eq "Stopped") {
        Write-Warning "Service is already stopped"
        return
    }
    
    try {
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
        $newStatus = Get-ServiceStatus
        if ($newStatus -eq "Stopped") {
            Write-Success "Service stopped successfully!"
        }
        else {
            Write-Error "Failed to stop service (Status: $newStatus)"
        }
    }
    catch {
        Write-Error "Stop error: $($_.Exception.Message)"
    }
}

# Show service status and info
function Show-ServiceStatus {
    Write-Info "YallahDPI Go Service Status"
    Write-Info "========================"
    
    $status = Get-ServiceStatus
    Write-Host "Service Status: " -NoNewline
    
    switch ($status) {
        "Running" { Write-Success $status }
        "Stopped" { Write-Warning $status }
        "NotInstalled" { Write-Error $status }
        default { Write-Warning $status }
    }
    
    if ($status -ne "NotInstalled") {
        Show-ServiceInfo
    }
    
    # Check if port is listening
    $listening = Get-NetTCPConnection -LocalPort 1080 -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        Write-Success "Proxy is listening on port 1080"
    }
    else {
        Write-Warning "Port 1080 is not listening"
    }
    
    # Show recent events
    Write-Info "`nRecent Events:"
    Get-EventLog -LogName Application -Source $ServiceName -Newest 3 -ErrorAction SilentlyContinue | 
        ForEach-Object { 
            $color = if ($_.EntryType -eq "Error") { "Red" } elseif ($_.EntryType -eq "Warning") { "Yellow" } else { "White" }
            Write-Host "  $($_.TimeGenerated) [$($_.EntryType)] $($_.Message)" -ForegroundColor $color
        }
}

# Show service information
function Show-ServiceInfo {
    if ((Get-ServiceStatus) -ne "NotInstalled") {
        $service = Get-Service -Name $ServiceName
        Write-Host "  Display Name: " -NoNewline; Write-Info $service.DisplayName
        Write-Host "  Start Type: " -NoNewline; Write-Info $service.StartType
        
        # Show config if exists
        $configFile = Join-Path $CurrentDir "yallahdpi-config.json"
        if (Test-Path $configFile) {
            Write-Host "  Config File: " -NoNewline; Write-Info $configFile
        }
    }
}

# Run in console mode
function Start-ConsoleMode {
    Write-Info "Starting YallahDPI in console mode..."
    Write-Warning "Press Ctrl+C to stop"
    Write-Info ""
    
    if (!(Test-Binary)) { return }
    
    try {
        & $BinaryPath console
    }
    catch {
        Write-Error "Console mode error: $($_.Exception.Message)"
    }
}

# Configure Windows Firewall
function Configure-Firewall {
    Write-Info "Configuring Windows Firewall..."
    
    # Remove existing rules
    Remove-NetFirewallRule -DisplayName "YallahDPI Go*" -ErrorAction SilentlyContinue
    
    # Add new rules
    New-NetFirewallRule -DisplayName "YallahDPI Go - Inbound" -Direction Inbound -Protocol TCP -LocalPort 1080 -Action Allow -Profile Domain,Private
    New-NetFirewallRule -DisplayName "YallahDPI Go - Outbound" -Direction Outbound -Program $BinaryPath -Action Allow -Profile Domain,Private
    
    Write-Success "Firewall rules configured!"
}

# Show usage instructions
function Show-ProxyInstructions {
    Write-Info ""
    Write-Info "==================================="
    Write-Info "  Proxy Configuration Instructions"
    Write-Info "==================================="
    Write-Host "Configure your applications to use:"
    Write-Success "  HTTP Proxy:  127.0.0.1:1080"
    Write-Success "  HTTPS Proxy: 127.0.0.1:1080"
    Write-Host ""
    Write-Host "Browser Examples:"
    Write-Host "  Firefox: Settings > Network Settings > Manual proxy"
    Write-Host "  Chrome:  chrome.exe --proxy-server=127.0.0.1:1080"
    Write-Host ""
    Write-Info "DPI Bypass Features Enabled:"
    Write-Success "  ✓ Split packets at position 4"
    Write-Success "  ✓ HTTP/HTTPS/UDP desync"
    Write-Success "  ✓ Host header space removal"
    Write-Success "  ✓ TLS record splitting at SNI"
    Write-Info ""
}

# Main script logic
Write-Host ""
Write-Host "YallahDPI Go Service Manager" -ForegroundColor Magenta
Write-Host "=========================" -ForegroundColor Magenta
Write-Host ""

# Check administrator privileges for service operations
if ($Install -or $Uninstall -or $Start -or $Stop) {
    if (!(Test-Administrator)) {
        Write-Error "Administrator privileges required for service operations"
        Write-Info "Please run PowerShell as Administrator"
        exit 1
    }
}

# Execute requested action
if ($Install) {
    Install-YallahDPIService
    Configure-Firewall
    Show-ProxyInstructions
}
elseif ($Uninstall) {
    Uninstall-YallahDPIService
}
elseif ($Start) {
    Start-YallahDPIService
    Show-ProxyInstructions
}
elseif ($Stop) {
    Stop-YallahDPIService
}
elseif ($Status) {
    Show-ServiceStatus
}
elseif ($Console) {
    Start-ConsoleMode
}
else {
    # Show current status and usage
    Show-ServiceStatus
    Write-Host ""
    Write-Info "Usage:"
    Write-Host "  .\install.ps1 -Install     Install service"
    Write-Host "  .\install.ps1 -Uninstall   Uninstall service"
    Write-Host "  .\install.ps1 -Start       Start service"
    Write-Host "  .\install.ps1 -Stop        Stop service"
    Write-Host "  .\install.ps1 -Status      Show status"
    Write-Host "  .\install.ps1 -Console     Run in console mode"
    Write-Host ""
}

Write-Host ""