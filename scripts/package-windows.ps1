param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tauri = Get-Content -LiteralPath (Join-Path $projectRoot 'src-tauri\tauri.conf.json') -Raw | ConvertFrom-Json
$package = Get-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Raw | ConvertFrom-Json
$cargo = Get-Content -LiteralPath (Join-Path $projectRoot 'src-tauri\Cargo.toml') -Raw
$match = [regex]::Match($cargo, '(?m)^version\s*=\s*"([^"]+)"')
if (-not $match.Success) { throw 'Could not read the Cargo package version.' }
$releaseVersion = [string]$tauri.version
if ($releaseVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Use a major.minor.patch version.' }
if ($releaseVersion -ne $package.version -or $releaseVersion -ne $match.Groups[1].Value) {
    throw 'The Tauri, npm, and Cargo versions must match.'
}

$source = Join-Path $projectRoot '.tools\target\release\gallery.exe'
$destination = Join-Path $projectRoot "dist\Gallery-$releaseVersion-Windows.exe"
if (Test-Path -LiteralPath $destination) { throw "Gallery $releaseVersion is already packaged. Bump the version before making another release." }

if (-not $SkipBuild) {
    $env:CARGO_HOME = Join-Path $projectRoot '.tools\cargo'
    $env:RUSTUP_HOME = Join-Path $projectRoot '.tools\rustup'
    $env:CARGO_TARGET_DIR = Join-Path $projectRoot '.tools\target'
    $env:CARGO_BUILD_JOBS = '2'
    $env:CARGO_NET_OFFLINE = 'true'
    Push-Location $projectRoot
    try {
        & (Join-Path $projectRoot '.tools\build-release.cmd')
        if ($LASTEXITCODE -ne 0) { throw "Windows build failed with exit code $LASTEXITCODE." }
    } finally { Pop-Location }
}

if (-not (Test-Path -LiteralPath $source)) { throw 'The Windows release executable is missing.' }
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'dist') -Force | Out-Null
Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
$stream = [System.IO.File]::OpenRead($destination)
try {
    $digest = [System.Security.Cryptography.SHA256]::Create().ComputeHash($stream)
    $hash = [System.BitConverter]::ToString($digest).Replace('-', '')
} finally {
    $stream.Dispose()
}
Write-Output $destination
Write-Output "SHA-256: $hash"
