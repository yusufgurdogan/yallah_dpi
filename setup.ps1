# Complete YallahDPI Setup - Run as Administrator
# This handles all PowerShell alias conflicts

Write-Host "=== YallahDPI Silent Global Setup ===" -ForegroundColor Cyan

# 1. Configure service for auto-start
Write-Host "Configuring auto-start..." -ForegroundColor Green
sc.exe config YallahDPIGo start= auto | Out-Null
sc.exe config YallahDPIGo type= own | Out-Null

# 2. Set service recovery options
Write-Host "Setting crash recovery..." -ForegroundColor Green
sc.exe failure YallahDPIGo reset= 0 actions= restart/5000/restart/5000/restart/5000 | Out-Null

# 3. Configure global proxy settings
Write-Host "Setting up global proxy..." -ForegroundColor Green

# User-level proxy (for browsers, etc.)
reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f | Out-Null
reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "127.0.0.1:1080" /f | Out-Null
reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride /t REG_SZ /d "localhost;127.*;10.*;172.16.*-172.31.*;192.168.*;<local>" /f | Out-Null

# System-level proxy (for Windows services)
netsh.exe winhttp set proxy proxy-server="127.0.0.1:1080" bypass-list="localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*" | Out-Null

Write-Host "`n=== Configuration Complete ===" -ForegroundColor Green

# 4. Verify everything
Write-Host "`nService Status:" -ForegroundColor Yellow
$service = Get-Service -Name YallahDPIGo -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "  Status: $($service.Status)" -ForegroundColor Green
    Write-Host "  Startup: $($service.StartType)" -ForegroundColor Green
} else {
    Write-Host "  Service not found!" -ForegroundColor Red
}

Write-Host "`nProxy Configuration:" -ForegroundColor Yellow
$proxyReg = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
if ($proxyReg.ProxyEnable -eq 1) {
    Write-Host "  User Proxy: Enabled ($($proxyReg.ProxyServer))" -ForegroundColor Green
} else {
    Write-Host "  User Proxy: Disabled" -ForegroundColor Red
}

# Check WinHTTP proxy
$winHttpProxy = netsh.exe winhttp show proxy
if ($winHttpProxy -like "*127.0.0.1:1080*") {
    Write-Host "  System Proxy: Enabled (127.0.0.1:1080)" -ForegroundColor Green
} else {
    Write-Host "  System Proxy: Not configured properly" -ForegroundColor Red
}

Write-Host "`n=== Testing Connection ===" -ForegroundColor Yellow

# Test connection through proxy
try {
    $response = Invoke-WebRequest -Uri "https://api.ipify.org/?format=json" -TimeoutSec 10 -ErrorAction Stop
    Write-Host "  Proxy test: SUCCESS" -ForegroundColor Green
    $ip = ($response.Content | ConvertFrom-Json).origin
    Write-Host "  Your IP: $ip" -ForegroundColor Green
} catch {
    Write-Host "  Proxy test: FAILED - $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Final Steps ===" -ForegroundColor Cyan
Write-Host "1. Reboot your computer to test auto-start" -ForegroundColor White
Write-Host "2. Your service will run silently in the background" -ForegroundColor White
Write-Host "3. All traffic will be routed through YallahDPI" -ForegroundColor White

# Optional: Create a quick status check script
$statusScript = @"
# YallahDPI Status Check
Write-Host "YallahDPI Status:" -ForegroundColor Cyan
Get-Service YallahDPIGo | Format-Table -AutoSize
netsh.exe winhttp show proxy
"@

$statusScript | Out-File -FilePath "check-status.ps1" -Encoding UTF8
Write-Host "`nCreated 'check-status.ps1' for future status checks" -ForegroundColor Green