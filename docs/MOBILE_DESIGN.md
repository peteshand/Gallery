# Mobile gallery design reference

The first prototype follows the current Google Photos Android structure where it suits a local library:

- A continuous chronological photo grid with no visible date headings, a two-card highlights carousel above it, and a full-screen photo viewer. Horizontal swipes navigate photos; swiping down or right from the left edge closes the viewer.
- A floating pill for Photos and [Collections](https://support.google.com/photos/thread/289829291/introducing-the-collections-view-find-what-you-need-faster?hl=en), with a separate round [Search](https://support.google.com/photos/answer/15235862?co=GENIE.Platform%3DAndroid&hl=en) button. A Create button is omitted until it has a real creation flow.
- Large rounded story covers, edge-to-edge thumbnails, narrow dark gutters, a dark canvas and system bars, and a compact profile-style Settings entry.

On Android, the gallery header, Settings panel, viewer toolbar, bottom navigation, and selection controls reserve space around the system status and gesture bars. The `0.7.8` APK contains these adjustments; physical phone confirmation is pending.

The first collection is the Takeout folder and Favourites is a separate quick-access collection. The current Search tab covers filenames, dates, collection names, and Takeout descriptions. People, places, image-content search, editing, sharing, and cloud backup need further implementation before those Google Photos affordances would be honest to show.

At 390 × 844 and 360 × 844 mobile viewports, a headless interaction check imported all 111 photos from `I:\Photos\Best of Poe 2`, opened the featured memory, swiped to the next photo, changed a favourite, and navigated Collections, Search, and Settings with no JavaScript exception or horizontal overflow. The screenshot files under `.tools` stay local because they contain personal photos.

Version 0.7.10 uses a light gray tile while a thumbnail loads. The photo viewer reserves the same image box for the thumbnail and 1920-pixel preview. Pinching the grid switches among five square columns, four square columns, and a larger aspect-preserving layout. Horizontal drags reveal the adjacent image before snapping; a downward drag dismisses the viewer. These changes need a physical Android check. Phone-camera import and automatic backup are planned; automatic backup will start off when implemented.

Version 0.7.11 aligns the Photos surface to the user's dark Google Photos screenshots. The top stories are a horizontal carousel; the photo stream is a single grid in descending capture time. The dense level has five square columns and occasional larger tiles. Finished backups do not place permanent green ticks over every thumbnail; active and failed backups remain visible. The floating navigation leaves photos visible behind it. The Android theme and web theme both request dark status/navigation surfaces. The 390-pixel headless render was inspected; the physical phone is still the acceptance check for system bar appearance and touch spacing.
