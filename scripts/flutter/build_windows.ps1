# PowerShell script for building Flutter Windows release and running Inno Setup
param(
    [string]$BuildName = "1.0.0",
    [string]$BuildNumber = "1",
    [string]$InnoScript = "build/windows/installer.iss"
)

$ErrorActionPreference = "Stop"

Write-Host "==> Building Flutter Windows (Release)..."
flutter build windows --release --build-name=$BuildName --build-number=$BuildNumber

$ReleaseDir = "build/windows/x64/runner/Release"
if (-not (Test-Path $ReleaseDir)) {
    # Fallback to standard runner path if x64 directory structure differs
    $ReleaseDir = "build/windows/runner/Release"
}

if (-not (Test-Path $ReleaseDir)) {
    Write-Error "Windows release directory not found at $ReleaseDir"
    exit 1
}

Write-Host "==> Successfully built Windows binaries at: $ReleaseDir"

if (Test-Path $InnoScript) {
    Write-Host "==> Compiling Inno Setup installer..."
    & "iscc.exe" "/DMyAppVersion=$BuildName" "/DSourceDir=$ReleaseDir" "$InnoScript"
    Write-Host "==> Windows Inno Setup installer generated successfully."
}
