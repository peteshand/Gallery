package gallery.logic;

class PhoneLogic extends Logic {
  @inject public var model:PhoneModel;
  @inject public var library:LibraryModel;
  @inject public var service:IGalleryService;
  var autoScanTimer:Null<Int> = null;

  override public function initialize():Void {
    model.supported.value = service.supportsPhoneMedia();
    model.accessRequested.add(requestAccess);
    model.refreshRequested.add(refresh);
    model.preferencesRequested.add(savePreferences);
    if (model.supported.value) service.getBackupPreferences().then(function(value) {
      model.preferences.value = value;
      updateAutoScan(value);
    })
      .catchError(function(error) model.message.value = 'Could not read backup settings: ' + Std.string(error));
    if (model.supported.value) service.getPhoneStatus().then(function(status) {
      model.status.value = status;
      if (status.access != 'none' && status.access != 'unsupported') refresh();
    }).catchError(function(error) model.message.value = 'Could not read phone photo access: ' + Std.string(error));
  }

  override public function dispose():Void {
    if (autoScanTimer != null) Browser.window.clearInterval(autoScanTimer);
    model.accessRequested.remove(requestAccess);
    model.refreshRequested.remove(refresh);
    model.preferencesRequested.remove(savePreferences);
  }

  function updateAutoScan(value:BackupPreferences):Void {
    if (autoScanTimer != null) Browser.window.clearInterval(autoScanTimer);
    autoScanTimer = value.autoBackup ? Browser.window.setInterval(function() {
      if (!model.busy.value && model.status.value != null && model.status.value.access == 'full') refresh();
    }, 60000) : null;
  }

  function requestAccess():Void {
    if (model.busy.value) return;
    model.busy.value = true;
    service.requestPhoneAccess().then(function(status) {
      model.status.value = status;
      model.busy.value = false;
      if (status.access == 'none') model.message.value = 'Photo access was not granted.';
      else refresh();
    }).catchError(function(error) {
      model.busy.value = false;
      model.message.value = 'Could not request photo access: ' + Std.string(error);
    });
  }

  function refresh():Void {
    if (model.busy.value) return;
    model.busy.value = true;
    model.message.value = 'Finding photos on this phone…';
    service.refreshPhoneMedia().then(function(result) {
      model.busy.value = false;
      model.status.value = {access:result.access,count:result.found};
      model.message.value = result.found + ' phone photos found' + (result.added == 0 ? '.' : ' · ' + result.added + ' new.');
      library.refreshRequested.dispatch();
    }).catchError(function(error) {
      model.busy.value = false;
      model.message.value = 'Could not read phone photos: ' + Std.string(error);
    });
  }

  function savePreferences(value:BackupPreferences):Void {
    if (model.busy.value) return;
    model.busy.value = true;
    service.setBackupPreferences(value).then(function(saved) {
      model.preferences.value = saved;
      updateAutoScan(saved);
      model.busy.value = false;
      model.message.value = 'Phone backup settings saved.';
    }).catchError(function(error) {
      model.busy.value = false;
      model.message.value = 'Could not save phone backup settings: ' + Std.string(error);
    });
  }
}
