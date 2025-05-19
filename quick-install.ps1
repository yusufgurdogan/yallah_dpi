# ByeDPI Quick Installer - Downloads and installs from GitHub releases
# Usage: iwr -useb https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/quick-install.ps1 | iex

Write-Host "🚀 ByeDPI Quick Installer" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

# Check admin privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ Administrator privileges required!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Create temp directory
$tempDir = "$env:TEMP\byedpi-quick-install"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    # Download latest release
    Write-Host "📥 Downloading latest release..." -ForegroundColor Green
    $apiUrl = "https://api.github.com/repos/yusufgurdogan/yallah_dpi/releases/latest"
    $release = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
    $asset = $release.assets | Where-Object { $_.name -like "*windows*.zip" -or $_.name -like "*.zip" } | Select-Object -First 1

    if (-not $asset) {
        # Fallback: try to get latest exe from repo
        Write-Host "📥 Downloading from main branch..." -ForegroundColor Yellow
        $exeUrl = "https://github.com/yusufgurdogan/yallah_dpi/releases/download/latest/byedpi.exe"
        $configUrl = "https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/byedpi-config.json"
        
        # Create install directory
        $installDir = "$env:ProgramFiles\ByeDPI"
        if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
        New-Item -ItemType Directory -Path $installDir | Out-Null
        
        # Download exe and config
        try {
            Invoke-WebRequest -Uri $exeUrl -OutFile "$installDir\byedpi.exe" -ErrorAction Stop
        } catch {
            # If release doesn't exist, build from source
            Write-Host "🔨 Building from source..." -ForegroundColor Yellow
            
            # Download source files
            $sourceFiles = @(
                @{url="https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/main.go"; file="main.go"},
                @{url="https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/go.mod"; file="go.mod"},
                @{url="https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/go.sum"; file="go.sum"}
            )
            
            foreach ($item in $sourceFiles) {
                Invoke-WebRequest -Uri $item.url -OutFile "$tempDir\$($item.file)"
            }
            
            # Check if Go is installed
            try {
                $null = Get-Command go -ErrorAction Stop
                Set-Location $tempDir
                go build -o "$installDir\byedpi.exe" main.go
                Write-Host "✅ Built successfully!" -ForegroundColor Green
            } catch {
                Write-Host "❌ Go not found. Installing Go..." -ForegroundColor Red
                
                # Download and install Go
                $goUrl = "https://go.dev/dl/go1.21.5.windows-amd64.msi"
                $goInstaller = "$tempDir\go.msi"
                Invoke-WebRequest -Uri $goUrl -OutFile $goInstaller
                Start-Process msiexec.exe -ArgumentList "/i $goInstaller /quiet" -Wait
                
                # Update PATH
                $env:PATH += ";C:\Program Files\Go\bin"
                
                # Try building again
                Set-Location $tempDir
                & "C:\Program Files\Go\bin\go.exe" build -o "$installDir\byedpi.exe" main.go
                Write-Host "✅ Go installed and built successfully!" -ForegroundColor Green
            }
        }
        
        # Download config
        try {
            Invoke-WebRequest -Uri $configUrl -OutFile "$installDir\byedpi-config.json"
        } catch {
            # Create default config if download fails
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
            $defaultConfig | ConvertTo-Json -Depth 10 | Out-File "$installDir\byedpi-config.json" -Encoding UTF8
        }
    } else {
        # Extract release zip
        Write-Host "📦 Extracting files..." -ForegroundColor Green
        $zipPath = "$tempDir\byedpi.zip"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
        
        $installDir = "$env:ProgramFiles\ByeDPI"
        if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
        New-Item -ItemType Directory -Path $installDir | Out-Null
        
        Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
    }

    # Find executable
    $exePath = Get-ChildItem -Path $installDir -Filter "*.exe" | Select-Object -First 1
    if (-not $exePath) {
        Write-Host "❌ No executable found!" -ForegroundColor Red
        exit 1
    }

    # Set working directory and install service
    Set-Location $installDir
    
    # Stop existing service if running
    Write-Host "🛑 Stopping existing service..." -ForegroundColor Yellow
    & $exePath.FullName stop 2>$null
    & $exePath.FullName uninstall 2>$null

    # Install and configure service
    Write-Host "⚙️ Installing service..." -ForegroundColor Green
    & $exePath.FullName install
    sc.exe config ByeDPIGo start= auto | Out-Null
    sc.exe failure ByeDPIGo reset= 0 actions= restart/5000/restart/5000/restart/5000 | Out-Null

    # Start service
    Write-Host "🚀 Starting service..." -ForegroundColor Green
    & $exePath.FullName start
    Start-Sleep -Seconds 2

    # Configure global proxy
    Write-Host "🌐 Setting up global proxy..." -ForegroundColor Green
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "127.0.0.1:1080" /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride /t REG_SZ /d "localhost;127.*;10.*;172.16.*-172.31.*;192.168.*;<local>" /f | Out-Null
    netsh.exe winhttp set proxy proxy-server="127.0.0.1:1080" bypass-list="localhost;127.*;192.168.*" | Out-Null

    # Verify installation
    Write-Host "`n✅ Installation Complete!" -ForegroundColor Green
    $service = Get-Service -Name ByeDPIGo -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Host "🎉 ByeDPI is running and ready!" -ForegroundColor Green
        Write-Host "🔒 DPI bypass is now active for all applications" -ForegroundColor Green
        Write-Host "🔄 Service will auto-start on boot" -ForegroundColor Green
        
        # Test connection
        try {
            $testResult = Invoke-WebRequest -Uri "http://httpbin.org/ip" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            Write-Host "🌍 Connection test: SUCCESS" -ForegroundColor Green
        } catch {
            Write-Host "⚠️ Connection test failed, but service is running" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ Service is not running. Check logs." -ForegroundColor Red
    }

} catch {
    Write-Host "❌ Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    # Cleanup
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
}

Write-Host "`nTo manage the service later:" -ForegroundColor Cyan
Write-Host "  Get-Service ByeDPIGo" -ForegroundColor White
Write-Host "  Or download the full manager from:" -ForegroundColor White  
Write-Host "  https://github.com/yusufgurdogan/yallah_dpi" -ForegroundColor White