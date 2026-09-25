package gallery.logic;

class SourceLogic extends Logic {
  @inject public var model:GalleryModel;
  @inject public var library:LibraryModel;
  @inject public var service:IGalleryService;

  override public function initialize():Void {
    model.cloudOnlyDevice.value = TauriGalleryService.isAvailable() && ~/Android/i.match(Browser.window.navigator.userAgent);
    model.canChooseSource.value = service.canChooseSource();
    if (model.canChooseSource.value) {
      var saved = Browser.window.localStorage.getItem('gallery.sourcePaths');
      var paths:Array<String> = saved == null ? [] : try haxe.Json.parse(saved) catch (_) [];
      if (paths == null) paths = [];
      var old = Browser.window.localStorage.getItem('gallery.sourcePath');
      if (old != null && old != '' && paths.indexOf(old) < 0) paths.push(old);
      model.sourcePaths.value = paths;
      model.sourcePath.value = paths.length > 0 ? paths[0] : null;
      persist();

    }
    service.getDefaultSource().then(function(path) {
      if (path != null && path != '' && model.sourcePaths.value.indexOf(path) < 0) add(path);
    }).catchError(function(error) library.error.value = 'Could not read import source: ' + Std.string(error));
    model.chooseSourceRequested.add(choose);
    model.removeSourceRequested.add(remove);
    model.importAllSourcesRequested.add(importAll);
  }

  override public function dispose():Void {
    model.chooseSourceRequested.remove(choose);
    model.removeSourceRequested.remove(remove);
    model.importAllSourcesRequested.remove(importAll);
  }

  function persist():Void {
    Browser.window.localStorage.setItem('gallery.sourcePaths', haxe.Json.stringify(model.sourcePaths.value));
    Browser.window.localStorage.removeItem('gallery.sourcePath');
  }

  function add(path:String):Void {
    var paths = model.sourcePaths.value.copy();
    if (paths.indexOf(path) >= 0) return;
    paths.push(path);
    model.sourcePaths.value = paths;
    model.sourcePath.value = paths[0];
    persist();
  }

  function remove(path:String):Void {
    var paths = model.sourcePaths.value.copy();
    var index = paths.indexOf(path);
    if (index < 0) return;
    paths.splice(index, 1);
    model.sourcePaths.value = paths;
    model.sourcePath.value = paths.length > 0 ? paths[0] : null;
    persist();
  }

  function importAll():Void {
    if (model.sourcePaths.value.length > 0) library.importSourcesRequested.dispatch(model.sourcePaths.value.copy());
  }

  function choose():Void service.chooseSource().then(function(path) {
    if (path != null) {
      add(path);
      library.importRequested.dispatch(path);
    }
  }).catchError(function(error) library.error.value = 'Could not choose folder: ' + Std.string(error));
}