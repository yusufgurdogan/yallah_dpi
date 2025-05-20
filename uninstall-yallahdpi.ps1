# YallahDPI Complete Uninstaller Script
# Run as Administrator

Write-Host "YallahDPI Complete Uninstaller" -ForegroundColor Red
Write-Host "===========================" -ForegroundColor Red
Write-Host ""

# Check for admin rights
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Administrator privileges required!" -ForegroundColor Red
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Ask for confirmation
Write-Host "This will completely remove YallahDPI from your system." -ForegroundColor Yellow
Write-Host "All proxy settings will be reset to default." -ForegroundColor Yellow
$confirm = Read-Host "Continue? (y/n)"
if ($confirm.ToLower() -ne "y") {
    Write-Host "Uninstallation cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host "Starting uninstallation process..." -ForegroundColor Cyan

# Step 1: Reset proxy settings
Write-Host "Resetting proxy settings..." -ForegroundColor Cyan
# Reset Internet Explorer/Edge proxy settings
reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f | Out-Null
reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /f 2>$null | Out-Null
# Reset WinHTTP proxy settings
netsh.exe winhttp reset proxy | Out-Null
Write-Host "Proxy settings reset successfully" -ForegroundColor Green

# Step 2: Remove firewall rules
Write-Host "Removing firewall rules..." -ForegroundColor Cyan
# Find and remove all YallahDPI-related firewall rules
Remove-NetFirewallRule -DisplayName "YallahDPI Go*" -ErrorAction SilentlyContinue | Out-Null
Write-Host "Firewall rules removed" -ForegroundColor Green

# Step 3: Stop and remove the service
Write-Host "Stopping YallahDPI service..." -ForegroundColor Cyan
# Check if service exists
$service = Get-Service -Name YallahDPIGo -ErrorAction SilentlyContinue
if ($service) {
    # First try to stop the service gracefully
    Stop-Service -Name YallahDPIGo -Force -ErrorAction SilentlyContinue
    # Then try to use the executable to properly uninstall
    $installDir = "$env:ProgramFiles\YallahDPI"
    if (Test-Path "$installDir\yallahdpi-go.exe") {
        & "$installDir\yallahdpi-go.exe" stop 2>$null
        & "$installDir\yallahdpi-go.exe" uninstall 2>$null
    }
    
    # As a last resort, use sc delete
    Start-Sleep -Seconds 2
    sc.exe delete YallahDPIGo 2>$null | Out-Null
    
    Write-Host "Service removed successfully" -ForegroundColor Green
} else {
    Write-Host "Service not found (already removed)" -ForegroundColor Green
}

# Step 4: Remove installation directory
Write-Host "Removing YallahDPI files..." -ForegroundColor Cyan
$installDir = "$env:ProgramFiles\YallahDPI"
if (Test-Path $installDir) {
    try {
        # Try to remove directory and all files
        Remove-Item -Path $installDir -Recurse -Force -ErrorAction Stop
        Write-Host "Program files removed successfully" -ForegroundColor Green
    } catch {
        Write-Host "Could not remove all files directly, trying alternative method..." -ForegroundColor Yellow
        # Try using cmd to force removal
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c rd /s /q `"$installDir`"" -Wait -WindowStyle Hidden
        Start-Sleep -Seconds 1
        
        if (Test-Path $installDir) {
            Write-Host "Warning: Some files could not be removed" -ForegroundColor Yellow
            Write-Host "You may need to restart and delete manually: $installDir" -ForegroundColor Yellow
        } else {
            Write-Host "Program files removed successfully" -ForegroundColor Green
        }
    }
} else {
    Write-Host "Installation directory not found (already removed)" -ForegroundColor Green
}

# Step 5: Clean registry
Write-Host "Cleaning registry..." -ForegroundColor Cyan
# Remove service registry entries
reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Services\YallahDPIGo" /f 2>$null | Out-Null
# Remove any other potential registry entries
reg.exe delete "HKLM\SOFTWARE\YallahDPI" /f 2>$null | Out-Null
Write-Host "Registry cleaned" -ForegroundColor Green

# Final verification
$serviceRemains = Get-Service -Name YallahDPIGo -ErrorAction SilentlyContinue
$proxyEnabled = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name "ProxyEnable" -ErrorAction SilentlyContinue).ProxyEnable -eq 1

Write-Host "`nUninstallation Results:" -ForegroundColor Cyan
if ($serviceRemains) {
    Write-Host "Service could not be completely removed" -ForegroundColor Red
    Write-Host "You may need to restart your computer to complete the removal" -ForegroundColor Yellow
} else {
    Write-Host "Service successfully removed" -ForegroundColor Green
}

if ($proxyEnabled) {
    Write-Host "System proxy is still enabled" -ForegroundColor Yellow
    Write-Host "To disable it manually, go to Windows Settings" -ForegroundColor Yellow
    Write-Host "Then go to Network and Internet -> Proxy" -ForegroundColor Yellow
} else {
    Write-Host "Proxy settings successfully reset" -ForegroundColor Green
}

if ((Test-Path $installDir)) {
    Write-Host "Some program files could not be removed" -ForegroundColor Yellow
    Write-Host "Location: $installDir" -ForegroundColor Yellow
} else {
    Write-Host "All program files removed" -ForegroundColor Green
}

if (!$serviceRemains -and !$proxyEnabled -and !(Test-Path $installDir)) {
    Write-Host "`nYallahDPI has been completely uninstalled!" -ForegroundColor Green
} else {
    Write-Host "`nYallahDPI has been partially uninstalled with some issues" -ForegroundColor Yellow
    Write-Host "You may need to restart your computer to complete the removal" -ForegroundColor Yellow
}

Write-Host "`nPress Enter to exit..." -ForegroundColor White
Read-Host