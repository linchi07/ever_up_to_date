param(
    [string]$BuildName = $env:BUILD_NAME,
    [string]$BuildNumber = $env:BUILD_NUMBER,
    [string]$InnoScript = "windows/installer.iss"
)
$ErrorActionPreference = "Stop"
if (-not $BuildName -or -not $BuildNumber) { throw "BUILD_NAME and BUILD_NUMBER are required" }
if (-not (Test-Path -LiteralPath $InnoScript)) { throw "Missing installer script: $InnoScript; run everup generate" }
if (-not $env:EVERUP_WINDOWS_SECRETS -and (Test-Path -LiteralPath ".everup/secrets.json")) {
    try {
        $local = Get-Content -Raw -LiteralPath ".everup/secrets.json" | ConvertFrom-Json
        if ($local.windows) { $env:EVERUP_WINDOWS_SECRETS = ($local.windows | ConvertTo-Json -Compress) }
    } catch {}
}
if ($env:EVERUP_WINDOWS_SECRETS) {
    try {
        $sec = $env:EVERUP_WINDOWS_SECRETS | ConvertFrom-Json
        if ($sec.certificate_base64) { $env:WINDOWS_CERTIFICATE_BASE64 = $sec.certificate_base64 }
        if ($sec.certificate_password) { $env:WINDOWS_CERTIFICATE_PASSWORD = $sec.certificate_password }
    } catch {}
}
if ($env:REQUIRE_PLATFORM_SIGNING -eq "true" -and -not $env:WINDOWS_CERTIFICATE_BASE64) { throw "Windows signing certificate is required" }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
flutter build windows --release --build-name=$BuildName --build-number=$BuildNumber
if ($LASTEXITCODE -ne 0) { throw "Flutter build failed" }
$ReleaseDir = "build/windows/x64/runner/Release"
if (-not (Test-Path -LiteralPath $ReleaseDir)) { $ReleaseDir = "build/windows/runner/Release" }
if (-not (Test-Path -LiteralPath $ReleaseDir)) { throw "Windows release directory not found" }
$Compiler = (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
if (-not $Compiler) { $Compiler = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe" }
if (-not (Test-Path -LiteralPath $Compiler)) { throw "Inno Setup compiler not found" }
& $Compiler "/DMyAppVersion=$BuildName" "/DSourceDir=$((Resolve-Path $ReleaseDir).Path)" $InnoScript
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed" }
$Installers = @(Get-ChildItem "build/windows/installer/*.exe")
if ($Installers.Count -ne 1) { throw "Expected one installer; clean build/windows/installer" }
if ($env:WINDOWS_CERTIFICATE_BASE64) {
    $Certificate = Join-Path $env:TEMP "everup-$([guid]::NewGuid()).pfx"
    try {
        [IO.File]::WriteAllBytes($Certificate, [Convert]::FromBase64String($env:WINDOWS_CERTIFICATE_BASE64))
        $SignTool = (Get-Command signtool.exe -ErrorAction SilentlyContinue).Source
        if (-not $SignTool) { $SignTool = (Get-ChildItem "${env:ProgramFiles(x86)}/Windows Kits/10/bin/*/x64/signtool.exe" | Sort-Object FullName -Descending | Select-Object -First 1).FullName }
        if (-not $SignTool) { throw "signtool.exe not found" }
        & $SignTool sign /fd SHA256 /f $Certificate /p $env:WINDOWS_CERTIFICATE_PASSWORD /tr https://timestamp.digicert.com /td SHA256 $Installers[0].FullName
        if ($LASTEXITCODE -ne 0) { throw "Authenticode signing failed" }
        & $SignTool verify /pa $Installers[0].FullName
        if ($LASTEXITCODE -ne 0) { throw "Authenticode verification failed" }
    } finally { Remove-Item -LiteralPath $Certificate -Force -ErrorAction SilentlyContinue }
}
Write-Host "Installer generated: $($Installers[0].FullName)"
