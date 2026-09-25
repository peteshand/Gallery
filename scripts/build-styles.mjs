import { readFileSync, writeFileSync } from 'node:fs';

const files = [
  'haxe/src/gallery/view/GalleryView.css',
  'haxe/src/gallery/view/library/LibraryView.css',
  'haxe/src/gallery/view/library/collection/CollectionCardView.css',
  'haxe/src/gallery/view/library/StoryCarouselView.css',
  'haxe/src/gallery/view/library/ThumbnailView.css',
  'haxe/src/gallery/view/viewer/ViewerView.css',
  'haxe/src/gallery/view/settings/SettingsView.css',
  'haxe/src/gallery/view/settings/source/SourceFoldersView.css',
  'haxe/src/gallery/view/settings/BackupView.css',
  'haxe/src/gallery/view/settings/phone/PhoneSourceView.css',
  'haxe/src/gallery/view/selection/SelectionBarView.css'
];
writeFileSync('web/style.css', files.map(file => readFileSync(file, 'utf8')).join('\n'));
