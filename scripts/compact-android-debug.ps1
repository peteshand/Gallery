$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$version = [string](Get-Content -LiteralPath (Join-Path $root 'src-tauri\tauri.conf.json') -Raw | ConvertFrom-Json).version
$source = Join-Path $root "dist\Gallery-$version-Android-arm64-debug.apk"
$destination = Join-Path $root "dist\Gallery-$version-Android-arm64-debug-compact.apk"
$zipalign = Join-Path $root '.tools\android-sdk\build-tools\36.0.0\zipalign.exe'
$apksigner = Join-Path $root '.tools\android-sdk\build-tools\36.0.0\apksigner.bat'
$env:JAVA_HOME = Join-Path $root '.tools\android-jdk\jdk-17.0.20.1+1'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
function Get-Sha256([string]$path) {
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return [System.BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}
foreach ($path in @($source,$zipalign,$apksigner)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing Android build input: $path" }
}
if ((Get-Item -LiteralPath $source).Length -gt 100MB) {
    throw 'The Gradle APK is too large for the compact alias. Rebuild with CARGO_PROFILE_DEV_STRIP=debuginfo.'
}
# Keep Gradle's ZIP entries intact. Android 11+ refuses compressed resources.arsc,
# and extractNativeLibs=false requires an uncompressed, page-aligned native .so.
$alignment = & $zipalign -c -P 16 -v 4 $source
if ($LASTEXITCODE -ne 0 -or
    -not ($alignment | Select-String 'resources\.arsc \(OK\)$') -or
    -not ($alignment | Select-String 'lib/arm64-v8a/libgallery_lib\.so \(OK\)$')) {
    throw 'Gradle APK resources or native library are compressed or misaligned.'
}
& $apksigner verify --verbose $source
if ($LASTEXITCODE -ne 0) { throw 'Gradle APK signature verification failed.' }
if (Test-Path -LiteralPath $destination) {
    $sourceHash = Get-Sha256 $source
    $existingHash = Get-Sha256 $destination
    if ($sourceHash -ne $existingHash) { throw 'The compact APK already exists with different content; bump the version.' }
} else {
    Copy-Item -LiteralPath $source -Destination $destination
}
$file = Get-Item -LiteralPath $destination
Write-Output $file.FullName
Write-Output "Bytes: $($file.Length)"
Write-Output "SHA-256: $(Get-Sha256 $destination)"
