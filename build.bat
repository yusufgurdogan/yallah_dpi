@echo off
echo Building YallahDPI Go Service...
echo.

REM Set build variables
set BINARY_NAME=YallahDPI-go.exe
set VERSION=1.0.0

REM Clean previous builds
if exist %BINARY_NAME% del %BINARY_NAME%
if exist YallahDPI-config.json del YallahDPI-config.json

REM Initialize Go module if not exists
if not exist go.mod (
    echo Initializing Go module...
    go mod init YallahDPI-go
    go get github.com/kardianos/service@latest
)

REM Tidy up dependencies
echo Downloading dependencies...
go mod tidy

REM Build for Windows
echo Building Windows executable...
set GOOS=windows
set GOARCH=amd64
set CGO_ENABLED=0

go build -ldflags="-w -s -X main.version=%VERSION%" -o %BINARY_NAME% .

if errorlevel 1 (
    echo Build failed!
    pause
    exit /b 1
)

echo.
echo Build completed successfully!
echo Generated: %BINARY_NAME%
echo.

REM Test the binary
echo Testing binary...
%BINARY_NAME% --help 2>nul
if errorlevel 1 (
    echo Warning: Binary test failed, but file was created
) else (
    echo Binary test passed!
)

echo.
echo =================================
echo YallahDPI Go Service Build Complete
echo =================================
echo.
echo To install as Windows service:
echo   1. Run as Administrator
echo   2. Execute: %BINARY_NAME% install
echo   3. Start: %BINARY_NAME% start
echo.
echo To test in console mode:
echo   Execute: %BINARY_NAME% console
echo.
pause