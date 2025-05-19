# ByeDPI Status Check
Write-Host "ByeDPI Status:" -ForegroundColor Cyan
Get-Service ByeDPIGo | Format-Table -AutoSize
netsh.exe winhttp show proxy
