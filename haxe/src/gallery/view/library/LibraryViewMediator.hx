package gallery.view.library;


class LibraryViewMediator extends Mediator {
  @inject public var view:LibraryView;
  @inject public var mediatorMap:IMediatorMap;
  @inject public var gallery:GalleryModel;
  @inject public var library:LibraryModel;
  var deferred = false;
  var pointerId = -1;
  var candidateId = '';
  var anchorId = '';
  var targetId = '';
  var active = false;
  var moved = false;
  var startX = 0.0;
  var startY = 0.0;
  var x = 0.0;
  var y = 0.0;
  var baseIds:Array<String> = [];
  var scrollTimer:haxe.Timer;
  var pinchStart:Null<Float>;

  override public function initialize():Void {
    mediatorMap.map(ThumbnailView).toMediator(ThumbnailViewMediator);
    mediatorMap.map(CollectionCardView).toMediator(CollectionCardViewMediator);
    mediatorMap.map(StoryCarouselView).toMediator(StoryCarouselViewMediator);
    gallery.tab.add(function(_) render());
    gallery.collection.add(function(_) render());
    gallery.cloudOnlyDevice.add(function(_) render());
    library.assets.add(function(_) render());
    library.loading.add(function(_) if (library.assets.value.length == 0) render());
    gallery.dragRequested.add(onDragRequested);
    gallery.gridDensity.add(function(value) view.showGridDensity(value)).fireOnAdd();
    view.element.addEventListener('touchstart', onPinchStart);
    view.element.addEventListener('touchend', onPinchEnd);
    view.element.addEventListener('touchcancel', onPinchCancel);
    view.element.addEventListener('touchmove', onPinchMove, cast {passive:false});
    view.element.addEventListener('click', onClick);
    view.element.addEventListener('input', function(_) if (view.searchInput != null) {
      gallery.query.value = view.searchInput.value;
      view.filterSearch(gallery.query.value);
    });
    Browser.document.addEventListener('pointermove', onPointerMove);
    Browser.document.addEventListener('pointerup', onPointerEnd);
    Browser.document.addEventListener('pointercancel', onPointerEnd);
    Browser.document.addEventListener('touchmove', onTouchMove, cast {passive:false});
    render();
  }

  override public function destroy():Void {
    gallery.dragRequested.remove(onDragRequested);
    Browser.document.removeEventListener('pointermove', onPointerMove);
    Browser.document.removeEventListener('pointerup', onPointerEnd);
    Browser.document.removeEventListener('pointercancel', onPointerEnd);
    Browser.document.removeEventListener('touchmove', onTouchMove);
    finish();
  }

  function render():Void {
    if (active) { deferred = true; return; }
    view.present(gallery.tab.value, library.assets.value, gallery.collection.value, gallery.query.value, library.loading.value, gallery.cloudOnlyDevice.value);
  }

  function onClick(event:js.html.MouseEvent):Void {
    var target:Element = cast event.target;
    if (target == null) return;
    var importControl = target.closest('.empty-state .primary-button');
    if (importControl != null) {
      if (importControl.textContent == 'View collections') gallery.tab.value = 'Collections';
      else if (gallery.cloudOnlyDevice.value) gallery.settingsOpen.value = true;
      else library.importRequested.dispatch(gallery.sourcePath.value);
      return;
    }
    var collection = target.closest('[data-collection]');
    if (collection != null) gallery.collection.value = collection.getAttribute('data-collection');
    if (target.closest('[data-collection-back]') != null) gallery.collection.value = null;
  }

  function onDragRequested(request:{id:String, pointerId:Int, x:Float, y:Float, immediate:Bool}):Void {
    finish();
    pointerId = request.pointerId;
    candidateId = request.id;
    startX = request.x;
    startY = request.y;
    if (request.immediate) start();
  }

  function onPointerMove(event:PointerEvent):Void {
    if (event.pointerId != pointerId) return;
    if (!active && candidateId != '' && (Math.abs(event.clientX - startX) > 12 || Math.abs(event.clientY - startY) > 12)) start();
    if (active) {
      event.preventDefault();
      x = event.clientX; y = event.clientY;
      if (Math.abs(x - startX) > 8 || Math.abs(y - startY) > 8) moved = true;
      updateRange();
    }
  }

  function onPointerEnd(event:PointerEvent):Void if (event.pointerId == pointerId) finish();
  function onTouchMove(event:TouchEvent):Void if (active) event.preventDefault();

  function onPinchStart(event:TouchEvent):Void {
    pinchStart = event.touches.length == 2 && !active ? pinchDistance(event.touches) : null;
    if (pinchStart != null) gallery.gridPinching.value = true;
  }

  function onPinchMove(event:TouchEvent):Void {
    if (pinchStart != null && event.touches.length == 2) event.preventDefault();
  }

  function onPinchEnd(event:TouchEvent):Void {
    if (pinchStart == null || event.touches.length != 1 || event.changedTouches.length != 1) return;
    var distance = pinchDistanceFromChanged(event);
    var ratio = distance / pinchStart;
    pinchStart = null;
    gallery.gridPinching.value = false;
    if (ratio > 1.15) gallery.gridDensity.value = Std.int(Math.min(2, gallery.gridDensity.value + 1));
    else if (ratio < 0.87) gallery.gridDensity.value = Std.int(Math.max(0, gallery.gridDensity.value - 1));
  }

  function onPinchCancel(_:TouchEvent):Void { pinchStart = null; gallery.gridPinching.value = false; }

  function pinchDistance(touches:js.html.TouchList):Float {
    var a = touches.item(0); var b = touches.item(1);
    var dx = a.clientX - b.clientX; var dy = a.clientY - b.clientY;
    return Math.sqrt(dx * dx + dy * dy);
  }

  function pinchDistanceFromChanged(event:TouchEvent):Float {
    var a = event.touches.item(0); var b = event.changedTouches.item(0);
    var dx = a.clientX - b.clientX; var dy = a.clientY - b.clientY;
    return Math.sqrt(dx * dx + dy * dy);
  }

  function start():Void {
    active = true;
    moved = false;
    anchorId = candidateId;
    targetId = anchorId;
    candidateId = '';
    x = startX; y = startY;
    baseIds = gallery.selectedIds.value.copy();
    if (baseIds.indexOf(anchorId) < 0) baseIds.push(anchorId);
    gallery.selectionAnchor.value = anchorId;
    gallery.selectedIds.value = baseIds.copy();
    scrollTimer = new haxe.Timer(40);
    scrollTimer.run = function() {
      if (!active || !moved) return;
      var bottom = Browser.window.innerHeight - 84;
      var amount = y > bottom - 72 ? 20 : y < 112 ? -20 : 0;
      if (amount != 0) { Browser.window.scrollBy(0, amount); updateRange(); }
    };
  }

  function updateRange():Void {
    if (!active) return;
    var tiles = view.element.querySelectorAll('.photo-tile:not(.hidden)');
    var ids = [for (index in 0...tiles.length) (cast tiles.item(index):Element).getAttribute('data-asset-id')];
    var from = ids.indexOf(anchorId);
    if (from < 0) return;
    var px = Math.max(0, Math.min(Browser.window.innerWidth - 1, x));
    var py = Math.max(66, Math.min(Browser.window.innerHeight - 96, y));
    var hit = Browser.document.elementFromPoint(px, py);
    var tile:Element = hit == null ? null : cast hit.closest('.photo-tile');
    var target = tile == null || !view.element.contains(tile) ? '' : tile.getAttribute('data-asset-id');
    if (target == '') {
      var nearest = Math.POSITIVE_INFINITY;
      for (index in 0...tiles.length) {
        var candidate:Element = cast tiles.item(index);
        var rect = candidate.getBoundingClientRect();
        if (rect.bottom < 64 || rect.top > Browser.window.innerHeight - 84) continue;
        var dx = Math.max(0, Math.max(rect.left - px, px - rect.right));
        var dy = Math.max(0, Math.max(rect.top - py, py - rect.bottom));
        var distance = dx * dx + dy * dy;
        if (distance < nearest) { nearest = distance; target = candidate.getAttribute('data-asset-id'); }
      }
    }
    var to = ids.indexOf(target);
    if (to < 0 || target == targetId) return;
    targetId = target;
    var next = baseIds.copy();
    for (index in Std.int(Math.min(from, to))...Std.int(Math.max(from, to)) + 1) if (next.indexOf(ids[index]) < 0) next.push(ids[index]);
    gallery.selectedIds.value = next;
  }

  function finish():Void {
    if (active && moved) gallery.dragClickSuppressedUntil.value = Date.now().getTime() + 150;
    active = false;
    moved = false;
    candidateId = '';
    pointerId = -1;
    anchorId = '';
    targetId = '';
    if (scrollTimer != null) { scrollTimer.stop(); scrollTimer = null; }
    if (deferred) { deferred = false; render(); }
  }
}
