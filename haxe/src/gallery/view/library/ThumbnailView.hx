package gallery.view.library;


class ThumbnailView extends DomContainer {
  public var asset(default, null):Asset;

  public function new(asset:Asset) {
    super('photo-tile', Browser.document.createElement('button'));
    this.asset = asset;
    element.setAttribute('data-asset-id', asset.id);
    element.setAttribute('data-taken-at', asset.takenAt);
    var image = Browser.document.createImageElement();
    var url = asset.thumbnailUrl == null ? asset.mediaUrl : asset.thumbnailUrl;
    if (url != '') image.src = url;
    image.alt = '';
    image.setAttribute('loading', 'lazy');
    element.appendChild(image);
    var check = Browser.document.createElement('span');
    check.className = 'selection-check hidden';
    element.appendChild(check);
    if (asset.syncState != null) {
      var badge = Browser.document.createElement('span');
      badge.className = 'sync-badge ' + asset.syncState;
      badge.textContent = switch (asset.syncState) {
        case 'synced': '✓';
        case 'preparing' | 'uploading': '↑';
        case 'failed': '!';
        default: '○';
      };
      badge.setAttribute('title', 'Backup: ' + StringTools.replace(asset.syncState, '_', ' '));
      element.appendChild(badge);
    }
  }

  public function showSelection(selecting:Bool, checked:Bool):Void {
    element.classList.toggle('selected', checked);
    element.setAttribute('aria-pressed', checked ? 'true' : 'false');
    element.setAttribute('aria-label', asset.filename + (checked ? ', selected' : ''));
    var check:Element = cast element.querySelector('.selection-check');
    check.classList.toggle('hidden', !selecting);
    check.classList.toggle('checked', checked);
    check.textContent = checked ? '✓' : '';
  }

  public function showImage(url:String):Void {
    var image:js.html.ImageElement = cast element.querySelector('img');
    if (image.getAttribute('src') == url) return;
    image.classList.remove('loaded');
    image.src = url;
  }

  public function showImageLoaded(loaded:Bool):Void {
    var image:js.html.ImageElement = cast element.querySelector('img');
    image.classList.toggle('loaded', loaded);
    if (loaded && image.naturalWidth > 0 && image.naturalHeight > 0) {
      var ratio = image.naturalWidth / image.naturalHeight;
      element.style.setProperty('--photo-ratio', image.naturalWidth + ' / ' + image.naturalHeight);
      element.style.setProperty('--photo-width-ratio', Std.string(Math.max(0.55, Math.min(2.5, ratio))));
      element.setAttribute('data-feature-landscape', ratio >= 1.55 && ratio <= 2.6 ? 'true' : 'false');
      updateFeature();
    }
  }

  function updateFeature():Void {
    if (element.parentElement == null) return;
    var siblings = element.parentElement.children;
    var index = -1;
    for (i in 0...siblings.length) if (siblings.item(i) == element) { index = i; break; }
    if (index < 0) return;
    var start = Std.int(Math.floor(index / 31)) * 31 + 17;
    var chosen = -1;
    for (i in start...Std.int(Math.min(start + 5, siblings.length))) {
      var candidate:Element = cast siblings.item(i);
      if (candidate.getAttribute('data-feature-landscape') == 'true') { chosen = i; break; }
    }
    for (i in start...Std.int(Math.min(start + 5, siblings.length))) {
      var candidate:Element = cast siblings.item(i);
      candidate.classList.toggle('featured-landscape', i == chosen);
    }
  }
}
