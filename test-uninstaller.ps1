<#
.SYNOPSIS
  Completely remove YallahDPI from Windows.

.DESCRIPTION
  • Stops and deletes the “YallahDPIGo” service
  • Clears WinHTTP & IE/Edge/Chrome proxy keys
  • Removes the Windows Firewall rule created by the installer
  • Deletes “C:\Program Files\YallahDPI” (and all contents)
  • Writes progress to the console; errors are silenced with *> $null
#>

# region ── Admin check ──────────────────────────────────────────────────────────
if (-not ([bool] ([Security.Principal.WindowsIdentity]::GetCurrent()).Groups -match 'S-1-5-32-544')) {
    Write-Host "`n[!]  Please run this script from an *elevated* PowerShell window." -ForegroundColor Yellow
    exit 1
}
# endregion

Write-Host "`n╔════════════════════════════════════════════════════════╗"
Write-Host   "║                  YallahDPI Uninstaller                ║"
Write-Host   "╚════════════════════════════════════════════════════════╝`n"

# region ── Stop & delete service ───────────────────────────────────────────────
Write-Host "➜ Stopping YallahDPIGo service..."
$svc = Get-Service -Name 'YallahDPIGo' -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq 'Running') { Stop-Service $svc -Force -ErrorAction SilentlyContinue }
    sc.exe delete YallahDPIGo *> $null
    Write-Host "  ✓ Service removed."
} else {
    Write-Host "  • Service not present."
}
# endregion

# region ── Reset proxy settings ────────────────────────────────────────────────
Write-Host "➜ Clearing WinHTTP proxy..."
netsh winhttp reset proxy *> $null

Write-Host "➜ Clearing user proxy keys..."
$inetKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
Set-ItemProperty $inetKey ProxyEnable 0 -ErrorAction SilentlyContinue
Remove-ItemProperty $inetKey ProxyServer -ErrorAction SilentlyContinue
Write-Host "  ✓ Proxy settings cleared."
# endregion

# region ── Remove firewall rule ────────────────────────────────────────────────
Write-Host "➜ Removing Windows Firewall rule..."
netsh advfirewall firewall delete rule name="YallahDPI" *> $null
Write-Host "  ✓ Firewall rule removed (if it existed)."
# endregion

# region ── Delete files ────────────────────────────────────────────────────────
$installDir = 'C:\Program Files\YallahDPI'
Write-Host "➜ Deleting files in '$installDir'..."
if (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ Folder removed."
} else {
    Write-Host "  • Folder not found."
}
# endregion

Write-Host "`n🎉  YallahDPI has been **completely removed**. You can close this window."
