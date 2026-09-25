package gallery.logic;


class MediaLogic extends Logic {
  @inject public var model:MediaModel;
  @inject public var service:IGalleryService;
  var pending = new Map<String, Bool>();

  override public function initialize():Void {
    model.requested.add(request);
    model.exportRequested.add(exportOriginal);
  }
  override public function dispose():Void {
    model.requested.remove(request);
    model.exportRequested.remove(exportOriginal);
  }

  function exportOriginal(asset:gallery.definitions.Asset):Void {
    model.exportMessage.value = 'Choose where to save the original photo…';
    service.exportOriginal(asset.id, asset.filename).then(function(saved) {
      model.exportMessage.value = saved ? 'Original photo saved.' : '';
    }).catchError(function(error) model.exportMessage.value = 'Could not save original: ' + Std.string(error));
  }

  function request(item:MediaRequest):Void {
    var key = item.id + ':' + item.variant;
    if (pending.exists(key)) return;
    pending.set(key, true);
    service.ensureMedia(item.id, item.variant).then(function(url) {
      pending.remove(key);
      var paths = model.paths.value.copy();
      paths.set(key, url);
      model.paths.value = paths;
    }).catchError(function(error) {
      pending.remove(key);
      model.error.value = 'Could not download photo: ' + Std.string(error);
    });
  }
}
