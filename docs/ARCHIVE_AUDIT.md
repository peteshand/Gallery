# Full Takeout archive preflight

Read-only inventory of `I:\Photos` on 2026-09-23. No files were imported, moved, or changed by this scan.

| Content | Files | Size (GiB) | Current importer |
| --- | ---: | ---: | --- |
| JPEG (`.jpg`, `.jpeg`) | 41,015 | 62.35 | Supported |
| PNG | 547 | 1.13 | Supported |
| GIF | 87 | 0.26 | Supported; stored original preserves animation |
| WebP | 15 | <0.01 | Supported |
| Takeout JSON sidecars | 42,308 | 0.03 | Paired with images |
| `.mp` motion-photo companions | 2,650 | 6.97 | Not imported |
| MP4 | 811 | 19.33 | Not imported |
| DNG | 28 | 0.03 | Not imported |
| Other video/companion files | 13 | about 1.00 | Not imported |

Total: 87,475 files in 102 top-level folders, 91.10 GiB. The supported image formats total 41,664 files and 63.74 GiB. The largest supported image is 28.4 MiB. A sampled `.MP` file begins with an ISO BMFF `ftypisom` header, consistent with an MP4-style video companion; it should not be decoded as a still image based on its extension.

All 42,308 JSON files parsed successfully. Eighty-two lack `photoTakenTime.timestamp`; the importer falls back to the source file's modification time when a photo's sidecar has no usable date. This count covers JSON files for both photos and video companions, so it is not a count of affected gallery photos.

The 111-photo `Best of Poe 2` end-to-end slice and a separate 354-photo 2007 import have passed. A real `Photos from 2016` folder test imported 968 photos in 1,840 seconds, verified Takeout dates and a duplicate-safe repeat pass, and cleaned its temporary catalogue. Peak observed process memory was about 118 MB while importing. A whole-archive run is still pending. Before expanding, decide how videos, motion companions, and DNG files should appear in the catalogue and run low-disk tests. Keep the source archive read only.
