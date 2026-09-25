package gallery.logic;


class CloudLogic extends Logic {
  @inject public var model:CloudModel;
  @inject public var library:LibraryModel;
  @inject public var service:IGalleryService;
  var polling = false;
  var lastSynced = -1;
  var wasRunning = false;
  var initialCatalogAttempted = false;
  var timer:haxe.Timer;

  override public function initialize():Void {
    model.available.value = service.canConfigureCloud();
    model.refreshRequested.add(refresh);
    model.saveRequested.add(save);
    model.removeRequested.add(remove);
    model.testRequested.add(test);
    model.syncRequested.add(sync);
    model.syncSelectedRequested.add(syncSelected);
    model.catalogRefreshRequested.add(refreshCatalog);
    model.cacheRefreshRequested.add(refreshCache);
    model.cacheLimitRequested.add(setCacheLimit);
    if (model.available.value) {
      refresh();
      refreshCache();
      poll();
      timer = new haxe.Timer(1500);
      timer.run = poll;
    }
  }

  override public function dispose():Void {
    model.refreshRequested.remove(refresh);
    model.saveRequested.remove(save);
    model.removeRequested.remove(remove);
    model.testRequested.remove(test);
    model.syncRequested.remove(sync);
    model.syncSelectedRequested.remove(syncSelected);
    model.catalogRefreshRequested.remove(refreshCatalog);
    model.cacheRefreshRequested.remove(refreshCache);
    model.cacheLimitRequested.remove(setCacheLimit);
    if (timer != null) timer.stop();
  }

  function refresh():Void service.getS3Connection().then(function(value) {
    model.connection.value = value;
    if (value.configured && value.credentialsAvailable && !initialCatalogAttempted) {
      initialCatalogAttempted = true;
      refreshCatalog();
    }
  }).catchError(function(_) model.message.value = 'Could not read local connection status.');

  function save(input:gallery.definitions.S3ConnectionInput):Void {
    model.busy.value = true;
    model.message.value = 'Saving connection locally…';
    service.saveS3Connection(input).then(function(value) {
      model.connection.value = value;
      model.message.value = 'Saved on this device. S3 access has not been tested yet.';
      model.busy.value = false;
      poll();
      if (!initialCatalogAttempted) {
        initialCatalogAttempted = true;
        refreshCatalog();
      }
    }).catchError(function(_) {
      model.message.value = 'Could not save the connection. Check the fields and try again.';
      model.busy.value = false;
    });
  }

  function remove():Void {
    model.busy.value = true;
    service.removeS3Connection().then(function(value) {
      model.connection.value = value;
      model.message.value = 'Connection removed from this device.';
      model.busy.value = false;
    }).catchError(function(_) {
      model.message.value = 'Could not remove the local connection.';
      model.busy.value = false;
    });
  }

  function test():Void {
    if (model.busy.value) return;
    model.busy.value = true;
    model.message.value = 'Checking S3 access…';
    var settled = false;
    var timeout = haxe.Timer.delay(function() {
      if (settled) return;
      settled = true;
      model.message.value = 'S3 connection check timed out after 30 seconds. Check the phone network and try again.';
      model.busy.value = false;
    }, 30000);
    service.testS3Connection().then(function(_) {
      if (settled) return;
      settled = true;
      timeout.stop();
      model.message.value = 'Read-only S3 connection check passed. Use Sync now to upload imported photos.';
      model.busy.value = false;
      refresh();
    }).catchError(function(error) {
      if (settled) return;
      settled = true;
      timeout.stop();
      model.message.value = 'S3 check failed: ' + Std.string(error);
      model.busy.value = false;
    });
  }

  function sync():Void {
    if (model.busy.value) return;
    model.busy.value = true;
    var cancelling = model.progress.value != null && model.progress.value.running;
    model.message.value = cancelling ? 'Requesting backup cancellation…' : 'Starting photo backup…';
    var request = cancelling ? service.cancelSync() : service.startSync();
    request.then(function(value) {
      model.progress.value = value;
      model.message.value = '';
      model.busy.value = false;
    }).catchError(function(error) {
      model.message.value = (cancelling ? 'Could not cancel backup: ' : 'Could not start backup: ') + Std.string(error);
      model.busy.value = false;
    });
  }

  function syncSelected(ids:Array<String>):Void {
    if (model.busy.value || ids.length == 0) return;
    model.busy.value = true;
    service.startSyncSelected(ids).then(function(value) {
      model.progress.value = value;
      model.message.value = 'Backing up ' + ids.length + (ids.length == 1 ? ' photo…' : ' photos…');
      model.busy.value = false;
      model.selectedSyncStarted.dispatch();
    }).catchError(function(error) {
      model.message.value = 'Could not start selected backup: ' + Std.string(error);
      model.busy.value = false;
    });
  }

  function poll():Void {
    if (polling) return;
    polling = true;
    service.getSyncStatus().then(function(value) {
      polling = false;
      model.progress.value = value;
      if (value.synced != lastSynced || value.preparing + value.uploading > 0 || (wasRunning && !value.running)) {
        lastSynced = value.synced;
        library.refreshRequested.dispatch();
      }
      wasRunning = value.running;
    }).catchError(function(_) polling = false);
  }

  function refreshCatalog():Void {
    if (model.catalogBusy.value) return;
    model.catalogBusy.value = true;
    model.message.value = 'Reading cloud catalogue…';
    service.refreshRemote().then(function(result) {
      model.catalogBusy.value = false;
      model.message.value = 'Cloud catalogue: ' + result.added + ' new, ' + result.updated + ' updated, ' + result.unchanged + ' unchanged'
        + (result.errors.length == 0 ? '.' : ', ' + result.errors.length + ' errors.');
      library.refreshRequested.dispatch();
      poll();
    }).catchError(function(error) {
      model.catalogBusy.value = false;
      model.message.value = 'Could not read cloud catalogue: ' + Std.string(error);
    });
  }

  function refreshCache():Void service.getCacheStatus().then(function(status) {
    model.cache.value = status;
  }).catchError(function(_) {});

  function setCacheLimit(bytes:Float):Void service.setCacheLimit(bytes).then(function(status) {
    model.cache.value = status;
    model.message.value = 'Photo cache limit saved.';
  }).catchError(function(error) model.message.value = 'Could not change cache limit: ' + Std.string(error));
}
