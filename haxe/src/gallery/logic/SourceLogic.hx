package gallery.logic;


class SourceLogic extends Logic {
  @inject public var model:GalleryModel;
  @inject public var library:LibraryModel;
  @inject public var service:IGalleryService;

  override public function initialize():Void {
    model.cloudOnlyDevice.value = TauriGalleryService.isAvailable() && ~/Android/i.match(Browser.window.navigator.userAgent);
    model.canChooseSource.value = service.canChooseSource();
    model.sourcePath.value = model.canChooseSource.value ? Browser.window.localStorage.getItem('gallery.sourcePath') : null;
    service.getDefaultSource().then(function(path) {
      if (model.sourcePath.value == null) model.sourcePath.value = path;
    }).catchError(function(error) library.error.value = 'Could not read import source: ' + Std.string(error));
    model.chooseSourceRequested.add(choose);
  }

  override public function dispose():Void model.chooseSourceRequested.remove(choose);

  function choose():Void service.chooseSource().then(function(path) {
    if (path != null) {
      model.sourcePath.value = path;
      Browser.window.localStorage.setItem('gallery.sourcePath', path);
    }
  }).catchError(function(error) library.error.value = 'Could not choose folder: ' + Std.string(error));
}
