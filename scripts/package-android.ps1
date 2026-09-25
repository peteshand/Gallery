param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tauri = Get-Content -LiteralPath (Join-Path $projectRoot 'src-tauri\tauri.conf.json') -Raw | ConvertFrom-Json
$package = Get-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Raw | ConvertFrom-Json
$cargo = Get-Content -LiteralPath (Join-Path $projectRoot 'src-tauri\Cargo.toml') -Raw
$cargoVersion = [regex]::Match($cargo, '(?m)^version\s*=\s*"([^"]+)"')
if (-not $cargoVersion.Success) { throw 'Could not read the Cargo package version.' }
$version = [string]$tauri.version
if ($version -notmatch '^\d+\.\d+\.\d+$' -or $version -ne $package.version -or $version -ne $cargoVersion.Groups[1].Value) {
    throw 'Tauri, npm, and Cargo must have the same major.minor.patch version.'
}
if (-not $SkipBuild) {
    Push-Location $projectRoot
    try {
        & (Join-Path $projectRoot 'scripts\build-android.cmd')
        if ($LASTEXITCODE -ne 0) { throw "Android build failed with exit code $LASTEXITCODE." }
    } finally { Pop-Location }
}
$source = Join-Path $projectRoot 'src-tauri\gen\android\app\build\outputs\apk\universal\debug\app-universal-debug.apk'
if (-not (Test-Path -LiteralPath $source)) { throw 'Android APK is missing.' }
$destination = Join-Path $projectRoot "dist\Gallery-$version-Android-arm64-debug.apk"
if (-not (Test-Path -LiteralPath $destination)) { Copy-Item -LiteralPath $source -Destination $destination }
function Hash-File($path) {
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $digest = [System.Security.Cryptography.SHA256]::Create().ComputeHash($stream)
        return [System.BitConverter]::ToString($digest).Replace('-', '')
    } finally { $stream.Dispose() }
}
$hash = Hash-File $destination
if ($hash -ne (Hash-File $source)) { throw "Gallery $version APK is already packaged with different content. Bump the version before making another release." }
Write-Output $destination
Write-Output "SHA-256: $hash"
