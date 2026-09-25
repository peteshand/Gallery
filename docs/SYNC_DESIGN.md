# Photo sync: Windows prototype

## Trigger and scope

Saving credentials and testing access never uploads a photo. **Sync now** in Settings starts an explicit batch for pending photos already imported on this device. A later import leaves new photos **Not synced** until a manual backup action. A photo's Details panel has its own **Back up now** button. On desktop, hold a photo or Ctrl-click (Command-click on Mac) to start a selection. Ctrl/Command-click toggles additional photos, Shift-click adds the range from the last selected photo, and an ordinary click clears the selection and opens that photo. On touch screens, long-press starts selection; taps toggle additional photos, and dragging across photos selects a continuous range. A finger near the top or bottom edge scrolls the page during a drag. The contextual bottom bar backs up the selection. While a backup runs, Settings offers **Cancel sync**. The worker finishes its current S3 object request, records it, and stops before the next object; remaining photos resume on a later backup action. Closing the app also pauses work. This keeps the 90 GB archive from uploading unexpectedly. Automatic background sync, scheduling, and cellular policy are later opt-in work.

The tested batch contains the 111 imported photos in `I:\Photos\Best of Poe 2`. The source files are read only. A photo is considered synced only after all four remote objects exist: original, preview, thumbnail, and metadata manifest.

## Objects

Under the configured `gallery/` prefix, each content SHA-256 ID owns:

* `originals/<id>.<source extension>` — untouched source bytes, including GIF animation.
* `previews/<id>.jpg` — orientation-corrected JPEG, maximum 1920 pixels on either side, quality 82, for the viewer. A JPEG no larger than 512 KiB and 1920 pixels with no orientation transform can be reused byte for byte to avoid an unnecessary re-encode.
* `thumbnails/<id>.jpg` — orientation-corrected, uncropped JPEG with a 320-pixel short side, quality 76. Very small sources are enlarged to reach 320 pixels. Layouts can crop this image in CSS without losing parts of the stored photo.

Starting in 0.5.0, the local thumbnail cache uses `thumbnail-v2.jpg` and manifests use version 2 with thumbnail width and height. The first launch upgrades old sync rows so completed photos show as pending. The next manual sync overwrites each remote thumbnail and manifest at their existing keys, while retaining completed original and preview uploads. No automatic upload starts during migration.
* `catalog/assets/<id>.json` — versioned metadata containing the ID, original filename, dates, collection, dimensions, sizes, object keys, description, location, and current favourite value at upload time. No local paths or credentials.

The manifest is uploaded last. Stable content-addressed keys make retries safe. The local SQLite row records `not_synced`, `preparing`, `uploading`, `synced`, or `failed`, a timestamp, and a short safe error message. A failed or interrupted batch can be retried at the object level. The UI shows the batch count and per-photo badges; only `synced` means the manifest and all three image objects were uploaded successfully. Changing a favourite marks its manifest for re-upload at the next manual sync.

The first live run completed all 111 test photos with zero failures. A read-only S3 listing found all 444 required objects. Locally, the originals total 168,317,966 bytes, previews 33,620,148 bytes, and thumbnails 2,112,776 bytes. A second run of the packaged engine exited successfully without re-uploading completed objects. A subsequent live test marked three manifests pending, backed up one selected photo, verified that the other two remained pending, then backed up just those two and returned the library to 111 synced photos.

Derivatives use the cross-platform Rust [`image` crate](https://docs.rs/image/0.25.10/image/) with JPEG, PNG, GIF, and WebP features, rather than a Windows imaging API. The current code decodes each full-resolution source before resizing; very large files need memory testing on Android before wider import. An Android ARM64 APK compiles, but photo operations have not been tested on a phone. macOS has not been compiled or tested, and HEIC and video decoding are not enabled.

## Fresh-device flow and changes

Gallery now lists and validates remote manifests into an empty local SQLite catalogue. On later refreshes, it records each manifest's S3 ETag for the configured bucket, region, endpoint, and prefix, then downloads only new or changed manifests. Missing ETags always cause a download. A read-only live test imported the 111 manifests and recognized them as unchanged on a second listing. Thumbnails download as tiles approach the viewport; previews download when a photo opens; originals download only through the viewer's explicit **Download original** action. The media cache defaults to 2 GB and has a 64 MB to 50 GB configurable limit. It tracks thumbnail and preview use in SQLite and evicts least recently used files before a download. A headless UI test confirmed viewport thumbnail requests, viewer preview loading, and the cache setting.

Favourite edits are written as immutable per-device events at `catalog/events/<device>/...`. A refresh uploads local pending events and replays remote events using a Lamport counter and device ID to resolve simultaneous edits. An isolated live S3 test passed exchanges between two simulated devices, including concurrent offline edits. Two physical devices have not yet been tested together. Remote-only assets are excluded from the original upload queue.

The current fresh-device refresh still lists every manifest and event key; a compressed catalogue snapshot and incremental cursor are needed for a large library. Deletions, album membership, and general metadata edits do not yet have event or tombstone semantics. Large originals need multipart upload and byte-level resume before expanding to 90 GB. GIF previews use a still frame; the original preserves animation. HEIC and video companions are outside this batch. Physical Android and cross-device acceptance remain pending.
