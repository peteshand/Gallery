# Gallery

Gallery is a personal photo prototype built with Haxe/Eva, Tauri 2, Rust, SQLite, and private S3 storage. The initial test set is the 111-photo `I:\Photos\Best of Poe 2` Takeout folder. Source photos are read only. The [delivery plan](PLAN.md) tracks the remaining work.

## Current builds

Versioned Windows and Android packages are generated in the local `dist/` directory, which is excluded from Git. The latest Windows standalone is `Gallery-0.11.1-Windows.exe`. The Windows installer and Android APK remain at 0.10.0; the new S3 layout and Takeout metadata support are currently available in the Windows standalone. See [Android instructions](docs/ANDROID.md) and [release history](docs/VERSIONS.md).

Desktop Settings now manages multiple source folders, scans them in sequence, and lets you opt into thumbnail-only viewing. Settings fills the window on both desktop and mobile, with the installed version shown beside the Settings heading and category pages for each group. Collections can also be browsed by year. Import and cloud backup remain separate explicit actions.

The 0.8.4 macOS build added the first tested Apple Silicon package. The reproducible macOS build command is `npm run release:macos`; see [release history](docs/VERSIONS.md) for its acceptance notes.

Android groups phone photos by source folder in Collections, keeps application folders such as WhatsApp out of the main Photos feed, shows collection covers, and uses a filled, justified layout at the largest grid setting. Phone acceptance remains separate from the macOS work.

## Repository and local data

This repository tracks source, project configuration, and the generated Android project files needed to rebuild the app. It excludes local photo catalogues (`data/`), release packages (`dist/`), downloaded toolchains (`.tools/`), JavaScript dependencies, generated UI bundles, and signing keys. S3 credentials are stored by the installed app in the operating system's protected credential store. Do not commit photo exports or credential files.

## What works

- Windows imports configured photo folders, reads Takeout dates, descriptions, locations and favourites, deduplicates by SHA-256, and browses by date, collection, and search. A recursive importer for larger Takeout folders uses durable per-file checkpoints, cancel and resume, and bounded JPEG derivatives without copying source originals. `I:\Photos\2003` passed an 18-photo real-data test; `I:\Photos\Photos from 2007` passed a 354-photo import and duplicate-safe repeat pass in 173 seconds with the 0.7.1 optimized build (481 seconds before the small-JPEG preview optimization).
- The shared Haxe UI supports a mobile grid, full-screen viewer, swipe navigation, desktop modifier selection, touch drag selection, and contextual **Back up now** actions. Gallery tiles are added in batches during scrolling.
- **Settings → Cloud storage** stores credentials in Windows Credential Manager. The macOS Keychain adapter passed persistence testing in 0.8.4; the current 0.11.1 source still needs a fresh Mac build and platform acceptance. Android Keystore support compiles and still needs device persistence testing. **Test connection** performs a read-only S3 check.
- Manual backup uploads the untouched original, a JPEG preview up to 1920 pixels, an aspect-preserving JPEG thumbnail with a 320-pixel short side, and a versioned JSON manifest. Progress, cancel, per-photo status, retries, and single or multi-photo backup are implemented. The 111-photo collection was uploaded and verified in S3.
- A fresh local catalogue can list remote manifests, fetch thumbnails near the viewport, fetch previews when opened, and download an original on explicit request. Repeat refreshes use S3 ETags to skip unchanged manifests. The media cache defaults to 2 GB, has a configurable limit, and evicts least recently used files. Favourite changes use immutable per-device S3 events. An isolated live S3 test passed two simulated devices, including concurrent offline edits.

## Build and test

Use Haxe 4.3+, Node.js 24+, and the Tauri/Rust prerequisites. `npm ci` installs JavaScript dependencies. `npm run build` compiles the Haxe UI. `npm run test:ui`, `GALLERY_MOCK_TAURI=1 npm run test:ui`, `npm run test:remote`, and `npm run test:android-ui` exercise the browser, native bridge mock, lazy remote media, and Android empty state. On macOS, set `GALLERY_SOURCE` to a local photo fixture folder for `test:ui` and `test:remote`; set `GALLERY_BROWSER_BIN` if Chrome is installed elsewhere. Run `cargo test --manifest-path src-tauri/Cargo.toml` for native tests, including a disposable Keychain round trip. To create the versioned macOS DMG, run `npm ci && npm run release:macos` with native-architecture Node.js 24+, Haxe 4.3+, Rust/Cargo, and Xcode Command Line Tools. It writes `dist/Gallery-<version>-macOS.dmg` and refuses to overwrite an existing package. Rust native tests also run through `.tools/test-native.cmd` on the configured Windows workspace.

`npm run release:windows:installer` builds the Windows NSIS installer. `npm run release:android` builds the ARM64 debug APK with the workspace-local JDK/SDK/NDK under `.tools`; `npm run release:android:compact` verifies it and creates a byte-identical alias. Versioned package files are not overwritten. See [version rules](docs/VERSIONS.md), [sync details](docs/SYNC_DESIGN.md), [credential setup](docs/CREDENTIALS.md), and [mobile design](docs/MOBILE_DESIGN.md).

## Remaining gates

Android credential persistence, offline cache, favourite convergence, and 0.7.10 viewer UI tests; macOS 0.10.1 build and current-source acceptance; HEIC and video support; compressed catalogue snapshots and incremental cursors; album and deletion event semantics; full-library stress and low-disk testing; production signing. The user confirmed Android S3 access and cloud photo loading with 0.7.6. The [91.10 GiB archive preflight](docs/ARCHIVE_AUDIT.md) identifies 41,664 supported images; the full archive has not been imported or uploaded.
