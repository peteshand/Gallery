package gallery.view.library;


class ThumbnailViewMediator extends Mediator {
  @inject public var view:ThumbnailView;
  @inject public var model:GalleryModel;
  @inject public var media:MediaModel;
  var hold:haxe.Timer;
  var pointerType = '';
  var pointerId = -1;
  var startX = 0.0;
  var startY = 0.0;
  var suppressClickUntil = 0.0;
  var observer:js.html.IntersectionObserver;

  override public function initialize():Void {
    var image:js.html.ImageElement = cast view.element.querySelector('img');
    image.addEventListener('load', function(_) view.showImageLoaded(true));
    image.addEventListener('error', function(_) view.showImageLoaded(false));
    if (image.complete && image.naturalWidth > 0) view.showImageLoaded(true);
    model.selectedIds.add(update).fireOnAdd();
    model.gridPinching.add(onPinching);
    media.paths.add(updateMedia).fireOnAdd();
    if (view.asset.mediaUrl == '' && view.asset.thumbnailUrl == null) {
      observer = new js.html.IntersectionObserver(function(entries, _) {
        for (entry in entries) if (entry.isIntersecting) {
          media.requested.dispatch({id:view.asset.id, variant:'thumbnail'});
          observer.disconnect();
          break;
        }
      }, {rootMargin:'240px'});
      observer.observe(view.element);
    }
    view.element.addEventListener('pointerdown', onDown);
    view.element.addEventListener('pointermove', onMove);
    view.element.addEventListener('pointerup', function(_) cancelHold());
    view.element.addEventListener('pointercancel', function(_) cancelHold());
    view.element.addEventListener('pointerleave', function(_) cancelHold());
    view.element.addEventListener('contextmenu', onContextMenu);
    view.element.addEventListener('click', onClick);
  }

  override public function destroy():Void {
    cancelHold();
    model.selectedIds.remove(update);
    model.gridPinching.remove(onPinching);
    media.paths.remove(updateMedia);
    if (observer != null) observer.disconnect();
  }

  function update(ids:Array<String>):Void view.showSelection(ids.length > 0, ids.indexOf(view.asset.id) >= 0);
  function onPinching(pinching:Bool):Void if (pinching) cancelHold();
  function updateMedia(paths:Map<String, String>):Void {
    var url = paths.get(view.asset.id + ':thumbnail');
    if (url != null) view.showImage(url);
  }
  function cancelHold():Void if (hold != null) { hold.stop(); hold = null; }

  function beginSelection():Void {
    cancelHold();
    suppressClickUntil = Date.now().getTime() + 750;
    var ids = model.selectedIds.value.copy();
    if (ids.indexOf(view.asset.id) < 0) ids.push(view.asset.id);
    model.selectionAnchor.value = view.asset.id;
    model.selectedIds.value = ids;
    if (pointerType == 'touch') model.dragRequested.dispatch({id:view.asset.id, pointerId:pointerId, x:startX, y:startY, immediate:true});
  }

  function onDown(event:PointerEvent):Void {
    if (model.gridPinching.value) return;
    if (event.button != 0) return;
    suppressClickUntil = 0;
    pointerType = event.pointerType;
    pointerId = event.pointerId;
    startX = event.clientX;
    startY = event.clientY;
    cancelHold();
    if (pointerType == 'touch' && model.selectedIds.value.length > 0) {
      model.dragRequested.dispatch({id:view.asset.id, pointerId:pointerId, x:startX, y:startY, immediate:false});
      return;
    }
    if (model.selectedIds.value.length == 0) hold = haxe.Timer.delay(beginSelection, 450);
  }

  function onMove(event:PointerEvent):Void {
    if (Math.abs(event.clientX - startX) > 12 || Math.abs(event.clientY - startY) > 12) cancelHold();
  }

  function onContextMenu(event:MouseEvent):Void {
    event.preventDefault();
    if (Date.now().getTime() < suppressClickUntil) return;
    if (model.selectedIds.value.length > 0) toggle(); else beginSelection();
  }

  function onClick(event:MouseEvent):Void {
    if (Date.now().getTime() < suppressClickUntil || Date.now().getTime() < model.dragClickSuppressedUntil.value) { suppressClickUntil = 0; return; }
    var clickPointerType:Dynamic = Reflect.field(event, 'pointerType');
    var touch = clickPointerType == 'touch' || (clickPointerType == null && pointerType == 'touch')
      || (clickPointerType == null && pointerType == '' && Browser.window.matchMedia('(pointer: coarse)').matches);
    if (touch && model.selectedIds.value.length > 0) toggle();
    else if (!touch && event.shiftKey) range();
    else if (!touch && (event.ctrlKey || event.metaKey)) toggle();
    else {
      model.selectedIds.value = [];
      model.activePhotoId.value = view.asset.id;
    }
  }

  function toggle():Void {
    var ids = model.selectedIds.value.copy();
    var index = ids.indexOf(view.asset.id);
    if (index >= 0) ids.splice(index, 1); else ids.push(view.asset.id);
    model.selectionAnchor.value = index < 0 ? view.asset.id : ids.length > 0 ? ids[0] : '';
    model.selectedIds.value = ids;
  }

  function range():Void {
    var tiles = Browser.document.querySelectorAll('#content .photo-tile');
    var visible = [for (index in 0...tiles.length) (cast tiles.item(index):js.html.Element).getAttribute('data-asset-id')];
    var anchor = model.selectionAnchor.value == '' ? (model.selectedIds.value.length > 0 ? model.selectedIds.value[0] : view.asset.id) : model.selectionAnchor.value;
    var from = visible.indexOf(anchor);
    var to = visible.indexOf(view.asset.id);
    if (from < 0 || to < 0) { toggle(); return; }
    var ids = model.selectedIds.value.copy();
    for (i in Std.int(Math.min(from, to))...Std.int(Math.max(from, to)) + 1) if (ids.indexOf(visible[i]) < 0) ids.push(visible[i]);
    model.selectedIds.value = ids;
  }
}
