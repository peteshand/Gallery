package gallery.view.viewer;


class ViewerViewMediator extends Mediator {
  @inject public var view:ViewerView;
  @inject public var gallery:GalleryModel;
  @inject public var library:LibraryModel;
  @inject public var cloud:CloudModel;
  @inject public var service:IGalleryService;
  @inject public var media:MediaModel;
  var touchX:Null<Float>;
  var touchY:Null<Float>;
  var dragging = false;

  override public function initialize():Void {
    view.initialize();
    gallery.cloudOnlyDevice.add(function(enabled) view.setAndroidInsets(enabled)).fireOnAdd();
    gallery.activePhotoId.add(function(_) {
      view.resetPhotoMotion();
      var asset = current();
      if (asset != null && asset.mediaUrl == '') media.requested.dispatch({id:asset.id, variant:media.thumbnailOnly.value ? 'thumbnail' : 'preview'});
      present();
    });
    gallery.detailsOpen.add(function(_) present());
    library.assets.add(function(_) present());
    media.paths.add(function(_) present());
    media.thumbnailOnly.add(function(_) present());
    media.exportMessage.add(function(_) present());
    cloud.connection.add(function(_) present());
    cloud.progress.add(function(_) present());
    cloud.message.add(function(_) present());
    cloud.busy.add(function(_) present());
    view.closeButton.addEventListener('click', function(_) gallery.activePhotoId.value = null);
    view.infoButton.addEventListener('click', function(_) gallery.detailsOpen.value = !gallery.detailsOpen.value);
    view.previousButton.addEventListener('click', function(_) move(-1));
    view.nextButton.addEventListener('click', function(_) move(1));
    view.favoriteButton.addEventListener('click', function(_) {
      var asset = current(); if (asset != null) library.favoriteRequested.dispatch(asset);
    });
    view.element.addEventListener('click', function(event:js.html.MouseEvent) if (view.backupButton != null && event.target == view.backupButton) {
      var asset = current(); if (asset != null) cloud.syncSelectedRequested.dispatch([asset.id]);
    });
    view.element.addEventListener('click', function(event:js.html.MouseEvent) if (view.downloadButton != null && event.target == view.downloadButton) {
      var asset = current(); if (asset != null) media.exportRequested.dispatch(asset);
    });
    view.stage.addEventListener('touchstart', function(event:TouchEvent) {
      if (event.touches.length != 1) { touchX = null; dragging = false; return; }
      var touch = event.touches.item(0); touchX = touch.clientX; touchY = touch.clientY;
      dragging = false;
    });
    view.stage.addEventListener('touchmove', function(event:TouchEvent) {
      if (touchX == null || event.touches.length != 1) return;
      var touch = event.touches.item(0);
      var dx = touch.clientX - touchX; var dy = touch.clientY - touchY;
      if (Math.abs(dx) < 8 && Math.abs(dy) < 8 && !dragging) return;
      dragging = true;
      event.preventDefault();
      view.dragPhoto(dx, dy);
    }, cast {passive:false});
    view.stage.addEventListener('touchend', function(event:TouchEvent) {
      if (touchX == null || event.changedTouches.length != 1) return;
      var touch = event.changedTouches.item(0);
      var startX = touchX;
      var dx = touch.clientX - startX; var dy = touch.clientY - touchY;
      touchX = null;
      dragging = false;
      if (dy > 90 && dy > Math.abs(dx) * 1.2) { view.dismissPhoto(); haxe.Timer.delay(function() gallery.activePhotoId.value = null, 180); }
      else if (startX < 40 && dx > 80 && dx > Math.abs(dy) * 1.3) { view.dismissPhoto(); haxe.Timer.delay(function() gallery.activePhotoId.value = null, 180); }
      else if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.3 && hasNeighbor(dx > 0 ? -1 : 1)) {
        var offset = dx > 0 ? -1 : 1;
        view.settlePhoto(offset);
        haxe.Timer.delay(function() move(offset), 180);
      } else { view.settlePhoto(0); view.element.style.transition = 'transform 180ms ease-out'; view.element.style.transform = ''; }
    });
    view.stage.addEventListener('touchcancel', function(_) { touchX = null; dragging = false; view.resetPhotoMotion(); });
    present();
  }

  function current():Asset {
    for (asset in library.assets.value) if (asset.id == gallery.activePhotoId.value) return asset;
    return null;
  }

  function present():Void {
    var asset = current();
    var connection = cloud.connection.value;
    var progress = cloud.progress.value;
    var backedUp = asset != null && asset.syncState == 'synced';
    var url = asset == null ? '' : asset.mediaUrl;
    if (asset != null && url == '') {
      var preview = media.paths.value.get(asset.id + (media.thumbnailOnly.value ? ':thumbnail' : ':preview'));
      if (preview == null) {
        media.requested.dispatch({id:asset.id, variant:media.thumbnailOnly.value ? 'thumbnail' : 'preview'});
        preview = media.paths.value.get(asset.id + ':thumbnail');
      }
      if (preview != null) url = preview;
    }
    view.present(asset, gallery.detailsOpen.value, service.canConfigureCloud(), backedUp || connection == null || !connection.configured, cloud.busy.value || (progress != null && progress.running), cloud.message.value, url, media.exportMessage.value);
    var index = asset == null ? -1 : library.assets.value.indexOf(asset);
    view.showNeighbors(index > 0 ? displayUrl(library.assets.value[index - 1]) : '', index >= 0 && index + 1 < library.assets.value.length ? displayUrl(library.assets.value[index + 1]) : '');
  }

  function displayUrl(asset:Asset):String {
    if (asset.mediaUrl != '') return asset.mediaUrl;
    var preview = media.thumbnailOnly.value ? null : media.paths.value.get(asset.id + ':preview');
    if (preview != null) return preview;
    var thumbnail = media.paths.value.get(asset.id + ':thumbnail');
    if (thumbnail == null) { media.requested.dispatch({id:asset.id, variant:'thumbnail'}); return ''; }
    return thumbnail;
  }

  function hasNeighbor(offset:Int):Bool {
    var assets = library.assets.value;
    var currentIndex = -1;
    for (index in 0...assets.length) if (assets[index].id == gallery.activePhotoId.value) { currentIndex = index; break; }
    return currentIndex + offset >= 0 && currentIndex + offset < assets.length;
  }

  function move(offset:Int):Void {
    var assets = library.assets.value;
    for (index in 0...assets.length) if (assets[index].id == gallery.activePhotoId.value) {
      var next = index + offset;
      if (next >= 0 && next < assets.length) {
        gallery.detailsOpen.value = false;
        gallery.activePhotoId.value = assets[next].id;
      }
      return;
    }
  }
}
