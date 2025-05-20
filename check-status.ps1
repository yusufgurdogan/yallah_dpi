# YallahDPI Status Check
Write-Host "YallahDPI Status:" -ForegroundColor Cyan
Get-Service YallahDPIGo | Format-Table -AutoSize
netsh.exe winhttp show proxy
