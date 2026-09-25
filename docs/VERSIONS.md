# Gallery versions and release files

Gallery uses `major.minor.patch` versions. A new feature increments minor, a compatible fix increments patch, and an incompatible change increments major. During the `0.x` prototype series, changes may still require a local catalogue migration; release notes must call that out.

Keep the version identical in `package.json`, `src-tauri/Cargo.toml`, and `src-tauri/tauri.conf.json`. The npm and Cargo lockfiles follow those manifests. Every packaged filename includes the app version, and the packaging scripts refuse to replace an existing versioned package.

## Current 0.10.2 prototype

| Platform | File | Status |
| --- | --- | --- |
| Windows installer | `dist/Gallery-0.10.0-Windows-Setup.exe` | Built |
| Windows standalone | `dist/Gallery-0.10.2-Windows.exe` | Built |
| Android ARM64 | `dist/Gallery-0.10.0-Android-arm64-debug-compact.apk` | Built; phone acceptance pending |
| macOS Apple Silicon | `dist/Gallery-0.8.4-macOS.dmg` | Prior 0.8.4 package built and core flow accepted; current 0.10.2 code needs a new macOS build and platform retest |

The compact APK is the file to transfer for manual phone installation. It has package ID `com.pshand.gallery`, version 0.10.0, and minimum Android API level 24. It is a byte-for-byte copy of the Gradle APK; the separate alias exists for the established download path. Debug signing is suitable for this prototype; a production release needs a dedicated signing key and upgrade policy. See [Android instructions](ANDROID.md) for the phone acceptance run.

Run `npm run release:windows` for the standalone executable. The installer and Android APK currently remain at 0.10.0; rebuild them at a later version when needed. On an Apple Silicon Mac, `npm ci && npm run release:macos` builds a versioned DMG with the local Tauri CLI. The release scripts check all three version manifests.

## Version history

- `0.10.2`: make a completed S3 catalogue listing clear backups deleted from the bucket, requeue matching local photos, remove stale cloud-only entries, and show verification progress. Windows standalone only.
- `0.10.1`: reconcile local photos with matching version-2 S3 manifests so prior uploads count as backed up after reimport. Windows standalone only.
- `0.10.0`: show the build version in Settings, organize Settings into category pages, and browse Collections by year.
- `0.9.1`: queue folders added during an active import and drop removed folders from pending scans.
- `0.9.0`: configure several desktop source folders, scan them in sequence, and remove folders without deleting imported photos. Existing single-folder preferences migrate. Add an opt-in thumbnail-only viewer setting and a full-window Settings layout. Android hides desktop folder controls. The app no longer silently chooses the development folder when no source is configured.
- `0.8.4`: add the reproducible macOS DMG build, pass the Keychain round-trip and S3 photo flow on Apple Silicon, and produce `Gallery-0.8.4-macOS.dmg`. The current 0.10.2 code has not been retested on macOS.

- `0.8.3`: retain the wide aspect ratio of featured tiles in the five-column grid.
- `0.8.2`: split Android device photos into Camera and app folders under Collections, keep app folders out of the main Photos feed, add photo covers to collection cards, use landscape featured tiles, and fill the widest grid with justified rows. Existing phone catalogue rows migrate on refresh.

- `0.8.1`: include phone photos awaiting backup in the settings backup count.
- `0.8.0`: discover Android camera-roll photos through MediaStore, show them in the chronological grid, back up selected photos with the existing original/preview/thumbnail/metadata pipeline, and add opt-in automatic backup with Wi-Fi and background options. Existing cloud objects and local catalogues migrate in place.

- `0.1.0`: first versioned Windows S3 upload prototype.
- `0.2.0`: single-photo and multi-photo backup actions.
- `0.3.0`: graceful backup cancellation.
- `0.4.0`: desktop modifier selection and touch range dragging.
- `0.4.1`: Haxe UI split into Eva views, mediators, CSS, models, and logic without changing photo or S3 storage formats.
- `0.5.0`: uncropped, aspect-preserving thumbnails. Existing backups become pending for thumbnail and manifest refresh; originals and previews are reused.
- `0.6.0`: fresh-device remote catalogue, lazy image fetch, LRU cache, favourite events, recursive Takeout import, and Windows installer.
- `0.6.1`: first compiled Android ARM64 debug APK and Android protected credential adapter.
- `0.6.2`: Android cloud-first UI, paged grid insertion, and compact debug APK.
- `0.6.3`: explicit Android keyring context initialization before WebView startup.
- `0.7.0`: S3 ETag based manifest refresh to skip unchanged manifests, plus current Android and Windows packages.
- `0.7.1`: clean up incomplete cache files after disk errors, reuse small unrotated JPEGs as previews, and validate a larger real Takeout folder.
- `0.7.2`: corrected native library storage, but its repack still compressed `resources.arsc`; it failed to install on the CMF Phone 2 Pro.
- `0.7.3`: strip Rust debug symbols during the Android build and distribute the verified Gradle APK intact, preserving uncompressed, aligned `resources.arsc` and native library entries. Physical installation is pending.
- `0.7.4`: keep per-file archive import errors in SQLite across runs, show the most recent failures in Settings, and clear an error after its file imports successfully.
- `0.7.5`: use the resumable importer for flat folders too. After 0.7.4 installed on Android but left its S3 check pending, add an explicit SDK timer, a bounded connection check, and clearer failure messages. Android cloud access still needs phone verification.
- `0.7.6`: bundle the verified Mozilla CA roots for the Android S3 client after 0.7.5 reported that its native root store contained no parseable certificates. Phone S3 connection and cloud photo loading were confirmed.
- `0.7.7`: move viewer controls clear of Android's system bars and add downward and left-edge swipe gestures to close a photo.
- `0.7.8`: apply Android safe-area spacing to the gallery header, Settings panel, navigation bar, and selection bar. Phone UI verification is pending.
- `0.7.9`: hide unloaded thumbnails and filenames, keep viewer photo size stable during preview loading, add three pinch-selectable grid layouts and drag-following viewer transitions. Phone verification is pending.

- `0.7.10`: prevent a two-finger pinch from starting long-press selection.
- `0.7.11`: use a dark mobile Photos screen with a large two-card story carousel, continuous chronological grid, five-column default density, quiet backup badges, floating navigation, and dark Android system bars.

Older descriptive prototype files are retained under `dist/legacy/`. A compiled package alone does not complete platform acceptance: Android device tests and macOS tests are still open.
