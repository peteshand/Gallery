#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

for command_name in node npm haxe rustc cargo; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The macOS release must be built on macOS." >&2
  exit 1
fi

node --input-type=module <<'NODE'
import { readFileSync } from 'node:fs';
const packageVersion = JSON.parse(readFileSync('package.json', 'utf8')).version;
const tauriVersion = JSON.parse(readFileSync('src-tauri/tauri.conf.json', 'utf8')).version;
const cargoVersion = readFileSync('src-tauri/Cargo.toml', 'utf8').match(/^version\s*=\s*"([^"]+)"/m)?.[1];
if (!/^\d+\.\d+\.\d+$/.test(packageVersion) || packageVersion !== tauriVersion || packageVersion !== cargoVersion) {
  throw new Error('package.json, Tauri, and Cargo versions must match as major.minor.patch.');
}
const nodeMajor = Number(process.versions.node.split('.')[0]);
if (nodeMajor < 24) throw new Error(`Node.js 24 or later is required (found ${process.versions.node}).`);
const haxeVersion = (await import('node:child_process')).execFileSync('haxe', ['--version'], { encoding: 'utf8' }).trim();
const haxeMajorMinor = haxeVersion.split('.').map(Number);
if (haxeMajorMinor[0] < 4 || (haxeMajorMinor[0] === 4 && haxeMajorMinor[1] < 3)) {
  throw new Error(`Haxe 4.3 or later is required (found ${haxeVersion}).`);
}
const rustHost = (await import('node:child_process')).execFileSync('rustc', ['-vV'], { encoding: 'utf8' }).match(/^host:\s*(\S+)/m)?.[1];
const rustArch = rustHost?.split('-')[0] === 'aarch64' ? 'arm64' : rustHost?.split('-')[0] === 'x86_64' ? 'x64' : null;
if (!rustArch || rustArch !== process.arch) {
  throw new Error(`Node and Rust must use the same native Mac architecture (Node ${process.arch}, Rust ${rustHost || 'unknown'}).`);
}
console.log(`Building Gallery ${packageVersion} for macOS (${process.arch}).`);
NODE

version="$(node -p "JSON.parse(require('node:fs').readFileSync('src-tauri/tauri.conf.json', 'utf8')).version")"
destination="$project_root/dist/Gallery-$version-macOS.dmg"
if [[ -e "$destination" ]]; then
  echo "Refusing to overwrite existing package: $destination" >&2
  exit 1
fi

if [[ ! -x node_modules/.bin/tauri ]]; then
  echo "Install project dependencies first with npm ci." >&2
  exit 1
fi

npm run build
npm run tauri:build -- --bundles dmg

bundle_dir="$project_root/src-tauri/target/release/bundle/dmg"
shopt -s nullglob
packages=("$bundle_dir"/*.dmg)
if [[ ${#packages[@]} -ne 1 ]]; then
  echo "Expected one Tauri DMG in $bundle_dir; found ${#packages[@]}." >&2
  exit 1
fi
mkdir -p "$project_root/dist"
cp "${packages[0]}" "$destination"
echo "Created $destination"
