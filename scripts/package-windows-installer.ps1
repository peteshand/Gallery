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
    $env:CARGO_HOME = Join-Path $projectRoot '.tools\cargo'
    $env:RUSTUP_HOME = Join-Path $projectRoot '.tools\rustup'
    $env:CARGO_TARGET_DIR = Join-Path $projectRoot '.tools\target'
    $env:CARGO_BUILD_JOBS = '2'
    $env:CARGO_NET_OFFLINE = 'true'
    Push-Location $projectRoot
    try {
        & (Join-Path $projectRoot 'scripts\build-windows-installer.cmd')
        if ($LASTEXITCODE -ne 0) { throw "Windows installer build failed with exit code $LASTEXITCODE." }
    } finally { Pop-Location }
}
$bundleDir = Join-Path $projectRoot '.tools\target\release\bundle\nsis'
$source = Get-ChildItem -LiteralPath $bundleDir -File -Filter '*.exe' | Where-Object {$_.Name -like "*$version*"} | Select-Object -First 1
if ($null -eq $source) { throw 'The NSIS installer was not produced.' }
$destination = Join-Path $projectRoot "dist\Gallery-$version-Windows-Setup.exe"
if (-not (Test-Path -LiteralPath $destination)) { Copy-Item -LiteralPath $source.FullName -Destination $destination }
$stream = [System.IO.File]::OpenRead($destination)
try {
    $digest = [System.Security.Cryptography.SHA256]::Create().ComputeHash($stream)
    $hash = [System.BitConverter]::ToString($digest).Replace('-', '')
} finally { $stream.Dispose() }
$sourceStream = [System.IO.File]::OpenRead($source.FullName)
try {
    $sourceDigest = [System.Security.Cryptography.SHA256]::Create().ComputeHash($sourceStream)
    $sourceHash = [System.BitConverter]::ToString($sourceDigest).Replace('-', '')
} finally { $sourceStream.Dispose() }
if ($hash -ne $sourceHash) { throw "Gallery $version installer is already packaged with different content. Bump the version before making another release." }
Write-Output $destination
Write-Output "SHA-256: $hash"
