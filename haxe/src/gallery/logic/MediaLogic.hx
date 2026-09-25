package gallery.logic;


class MediaLogic extends Logic {
  @inject public var model:MediaModel;
  @inject public var service:IGalleryService;
  var pending = new Map<String, Bool>();

  override public function initialize():Void {
    model.thumbnailOnly.value = Browser.window.localStorage.getItem("gallery.thumbnailOnly") == "true";
    model.thumbnailOnly.add(saveDownloadPreference);
    model.requested.add(request);
    model.exportRequested.add(exportOriginal);
  }
  override public function dispose():Void {
    model.requested.remove(request);
    model.thumbnailOnly.remove(saveDownloadPreference);
    model.exportRequested.remove(exportOriginal);
  }

  function saveDownloadPreference(enabled:Bool):Void Browser.window.localStorage.setItem("gallery.thumbnailOnly", enabled ? "true" : "false");
  function exportOriginal(asset:gallery.definitions.Asset):Void {
    model.exportMessage.value = 'Choose where to save the original photo…';
    service.exportOriginal(asset.id, asset.filename).then(function(saved) {
      model.exportMessage.value = saved ? 'Original photo saved.' : '';
    }).catchError(function(error) model.exportMessage.value = 'Could not save original: ' + Std.string(error));
  }

  function request(item:MediaRequest):Void {
    var variant = model.thumbnailOnly.value && item.variant == "preview" ? "thumbnail" : item.variant;
    var key = item.id + ':' + variant;
    if (pending.exists(key) || model.paths.value.exists(key)) return;
    pending.set(key, true);
    service.ensureMedia(item.id, variant).then(function(url) {
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
