# YallahDPI Uninstaller
Write-Host "YallahDPI Uninstaller" -ForegroundColor Red
Write-Host "================" -ForegroundColor Red

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Administrator privileges required!" -ForegroundColor Red
    exit 1
}

# Ask for confirmation
Write-Host "Bu islem YallahDPI'i tamamen kaldiracak." -ForegroundColor Yellow
$confirm = Read-Host "Devam etmek istiyor musunuz? (e/h)"
if ($confirm.ToLower() -ne "e") {
    Write-Host "Kaldirma islemi iptal edildi." -ForegroundColor Yellow
    exit 0
}

# Reset proxy settings
Write-Host "Proxy ayarlari sifirlaniyor..." -ForegroundColor Yellow
reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f | Out-Null
reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /f 2>$null | Out-Null
netsh.exe winhttp reset proxy | Out-Null

# Remove firewall rules
Write-Host "Guvenlik duvari kurallari kaldiriliyor..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "YallahDPI Go*" -ErrorAction SilentlyContinue | Out-Null

# Stop and uninstall service
Write-Host "Servis durduruluyor..." -ForegroundColor Yellow
Stop-Service -Name YallahDPIGo -Force -ErrorAction SilentlyContinue

$installDir = "$env:ProgramFiles\YallahDPI"
if (Test-Path "$installDir\yallahdpi-go.exe") {
    & "$installDir\yallahdpi-go.exe" stop 2>$null
    & "$installDir\yallahdpi-go.exe" uninstall 2>$null
}

# Make sure service is deleted
sc.exe delete YallahDPIGo 2>$null | Out-Null

# Remove installation folder
Write-Host "Program dosyalari kaldiriliyor..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

try {
    # Try to remove directory and all files
    Remove-Item -Path $installDir -Recurse -Force -ErrorAction Stop
    Write-Host "Dosyalar basariyla kaldirildi" -ForegroundColor Green
} catch {
    Write-Host "Bazi dosyalar kaldirilamadi, alternatif yontem deneniyor..." -ForegroundColor Yellow
    # Try using cmd to force removal
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c rd /s /q `"$installDir`"" -Wait -WindowStyle Hidden
    Start-Sleep -Seconds 1
    
    if (Test-Path $installDir) {
        Write-Host "Uyari: Bazi dosyalar kaldirilamadi" -ForegroundColor Yellow
        Write-Host "Bilgisayarinizi yeniden baslatip manuel olarak silebilirsiniz: $installDir" -ForegroundColor Yellow
    } else {
        Write-Host "Dosyalar basariyla kaldirildi" -ForegroundColor Green
    }
}

# Final verification
$serviceRemains = Get-Service -Name YallahDPIGo -ErrorAction SilentlyContinue
$proxyEnabled = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name "ProxyEnable" -ErrorAction SilentlyContinue).ProxyEnable -eq 1

if (!$serviceRemains -and !$proxyEnabled -and !(Test-Path $installDir)) {
    Write-Host "`nYallahDPI tamamen kaldirildi!" -ForegroundColor Green
} else {
    Write-Host "`nYallahDPI kismen kaldirildi, bazi sorunlar olustu" -ForegroundColor Yellow
    Write-Host "Islemi tamamlamak için bilgisayarinizi yeniden baslatmaniz gerekebilir" -ForegroundColor Yellow
}

Write-Host "`nCikmak için Enter tusuna basin..." -ForegroundColor White
Read-Host