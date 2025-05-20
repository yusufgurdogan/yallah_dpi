<#  YallahDPI Uninstaller
    Version: 2025-05-20
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#------------------------------------------------------------------------------#
function Require-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        Write-Host "❌  Please re-launch PowerShell **as Administrator**" -ForegroundColor Red
        exit 1
    }
}

function Reset-Proxy {
    Write-Host "• Resetting user + WinHTTP proxy…" -ForegroundColor Yellow
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
                /v ProxyEnable /t REG_DWORD /d 0 /f | Out-Null
    reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
                  /v ProxyServer /f 2>$null | Out-Null
    netsh.exe winhttp reset proxy | Out-Null
}

function Remove-FirewallRules {
    Write-Host "• Removing firewall rules…" -ForegroundColor Yellow
    Get-NetFirewallRule -DisplayName "YallahDPI Go*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
}

function Stop-And-Delete-Service {
    param([string]$Name)

    Write-Host "• Stopping Windows service '$Name' (if present)…" -ForegroundColor Yellow
    Get-Service -Name $Name -ErrorAction SilentlyContinue | %{
        if ($_.Status -eq 'Running') { Stop-Service $_ -Force }
    }

    sc.exe delete $Name 2>$null | Out-Null
}

function Remove-InstallFolder {
    param([string]$Path)

    # Leave the folder before removing it
    if ($PWD.Path -like "$Path*") { Set-Location ([System.IO.Path]::GetTempPath()) }

    Write-Host "• Removing program files…" -ForegroundColor Yellow
    Start-Sleep 2
    try {
        Remove-Item -Path $Path -Recurse -Force
        Write-Host "  ✔ Files deleted." -ForegroundColor Green
    }
    catch {
        Write-Host "  ⚠ Some files were locked, retrying with cmd…" -ForegroundColor Yellow
        Start-Process cmd.exe "/c rd /s /q `"$Path`"" -WindowStyle Hidden -Wait
        if (Test-Path $Path) {
            Write-Host "  ⚠ Manual deletion may be required: $Path" -ForegroundColor Yellow
        } else {
            Write-Host "  ✔ Files deleted." -ForegroundColor Green
        }
    }
}

#------------------------------------------------------------------------------#
Require-Admin

$installDir = Join-Path $env:ProgramFiles 'YallahDPI'
$serviceExe = Join-Path $installDir 'yallahdpi-go.exe'

Reset-Proxy
Remove-FirewallRules
Stop-And-Delete-Service -Name 'YallahDPIGo'

# Ask the helper binary (if it exists) to uninstall itself too
if (Test-Path $serviceExe) {
    & $serviceExe stop      2>$null
    & $serviceExe uninstall 2>$null
}

Remove-InstallFolder -Path $installDir

Write-Host "`nYallahDPI has been fully uninstalled. ✔" -ForegroundColor Green
#------------------------------------------------------------------------------#
