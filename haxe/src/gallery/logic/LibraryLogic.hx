package gallery.logic;


class LibraryLogic extends Logic {
  @inject public var model:LibraryModel;
  @inject public var gallery:GalleryModel;
  @inject public var service:IGalleryService;
  var importing:Bool;
  var importQueue:Array<String>;
  var importTimer:haxe.Timer;

  override public function initialize():Void {
    importing = false;
    importQueue = [];
    model.importRequested.add(importSource);
    model.importSourcesRequested.add(importSources);
    gallery.removeSourceRequested.add(removeQueuedSource);
    model.favoriteRequested.add(toggleFavorite);
    model.refreshRequested.add(refresh);
    model.cancelImportRequested.add(cancelImport);
    model.importErrorsRequested.add(refreshImportErrors);
    refresh();
  }

  override public function dispose():Void {
    model.importRequested.remove(importSource);
    model.importSourcesRequested.remove(importSources);
    gallery.removeSourceRequested.remove(removeQueuedSource);
    model.favoriteRequested.remove(toggleFavorite);
    model.refreshRequested.remove(refresh);
    model.cancelImportRequested.remove(cancelImport);
    model.importErrorsRequested.remove(refreshImportErrors);
    if (importTimer != null) importTimer.stop();
  }

  public function refresh():Void {
    model.loading.value = true;
    service.listAssets().then(function(assets) {
      assets.sort(function(a, b) {
        if (a.takenAt > b.takenAt) return -1;
        if (a.takenAt < b.takenAt) return 1;
        return Reflect.compare(a.filename, b.filename);
      });
      model.assets.value = assets;
      model.loading.value = false;
    }).catchError(function(error) {
      model.error.value = Std.string(error);
      model.loading.value = false;
    });
  }

  function importSources(paths:Array<String>):Void {
    if (paths.length == 0) return;
    for (path in paths) if (importQueue.indexOf(path) < 0) importQueue.push(path);
    if (!importing) importNext();
  }
  function removeQueuedSource(path:String):Void importQueue = importQueue.filter(function(queued) return queued != path);
  function importNext():Void {
    if (importQueue.length == 0) return;
    importSource(importQueue.shift());
  }
  public function importSource(?source:String):Void {
    if (importing) {
      if (source != null && importQueue.indexOf(source) < 0) importQueue.push(source);
      return;
    }
    importing = true;
    model.loading.value = true;
    model.error.value = null;
    model.status.value = 'Importing photos…';
    if (importTimer != null) importTimer.stop();
    importTimer = new haxe.Timer(600);
    importTimer.run = pollImport;
    service.importSource(source).then(function(result) {
      importTimer.stop();
      model.importProgress.value = null;
      var summary = 'Imported ' + result.added + ' photos · ' + result.existing + ' already in library';
      model.status.value = summary;
      haxe.Timer.delay(function() if (model.status.value == summary) model.status.value = '', 5000);
      if (result.errors.length > 0) model.error.value = result.errors.join('\n');
      refreshImportErrors();
      refresh();
      importing = false;
      importNext();
    }).catchError(function(error) {
      importTimer.stop();
      model.importProgress.value = null;
      model.error.value = Std.string(error);
      model.loading.value = false;
      importing = false;
      importNext();
    });
  }

  function pollImport():Void service.getImportProgress().then(function(progress) {
    model.importProgress.value = progress;
    if (progress.running && progress.processed > 0)
      model.status.value = 'Importing ' + progress.processed + ' photos · ' + progress.current;
  }).catchError(function(_) {});

  function cancelImport():Void {
    importQueue = [];
    service.cancelImport().then(function(_) {
    model.status.value = 'Stopping import after the current photo…';
  }).catchError(function(error) model.error.value = Std.string(error));
  }

  function refreshImportErrors():Void service.listImportErrors().then(function(errors) {
    model.importErrors.value = errors;
  }).catchError(function(error) model.error.value = Std.string(error));

  public function toggleFavorite(asset:Asset):Void {
    service.setFavorite(asset.id, !asset.favorite).then(function(_) refresh()).catchError(function(error) {
      model.error.value = Std.string(error);
    });
  }
}
