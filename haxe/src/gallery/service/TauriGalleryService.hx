package gallery.service;


class TauriGalleryService implements IGalleryService {
  public function new() {}

  public static function isAvailable():Bool return Reflect.field(Browser.window, '__TAURI__') != null;

  public function listAssets():Promise<Array<Asset>> {
    return invoke('list_assets').then(function(value:Dynamic) {
      var assets:Array<Asset> = cast value;
      for (asset in assets) if (asset.mediaUrl != '') asset.mediaUrl = fileUrl(asset.mediaUrl);
      for (asset in assets) if (asset.thumbnailUrl != null) asset.thumbnailUrl = fileUrl(asset.thumbnailUrl);
      return assets;
    });
  }

  public function importSource(?source:String):Promise<ImportResult> return invoke('import_source', {source: source});
  public function getImportProgress():Promise<ImportProgress> return invoke('get_import_progress');
  public function listImportErrors():Promise<Array<ImportError>> return invoke('list_import_errors');
  public function cancelImport():Promise<Dynamic> return invoke('cancel_import');

  public function setFavorite(id:String, favorite:Bool):Promise<Asset> {
    return invoke('set_favorite', {id: id, favorite: favorite}).then(function(value:Dynamic) {
      var asset:Asset = cast value;
      if (asset.mediaUrl != '') asset.mediaUrl = fileUrl(asset.mediaUrl);
      if (asset.thumbnailUrl != null) asset.thumbnailUrl = fileUrl(asset.thumbnailUrl);
      return asset;
    });
  }

  public function canChooseSource():Bool return !~/Android/i.match(Browser.window.navigator.userAgent);

  public function getDefaultSource():Promise<Null<String>> return invoke('get_default_source');

  public function canConfigureCloud():Bool return true;
  public function supportsPhoneMedia():Bool return ~/Android/i.match(Browser.window.navigator.userAgent);
  public function getPhoneStatus():Promise<PhoneStatus> return invoke('get_phone_status');
  public function requestPhoneAccess():Promise<PhoneStatus> return invoke('request_phone_access');
  public function refreshPhoneMedia():Promise<PhoneRefresh> return invoke('refresh_phone_media');
  public function getBackupPreferences():Promise<BackupPreferences> return invoke('get_backup_preferences');
  public function setBackupPreferences(preferences:BackupPreferences):Promise<BackupPreferences> return invoke('set_backup_preferences', {preferences:preferences});
  public function getS3Connection():Promise<S3ConnectionStatus> return invoke('get_s3_connection');
  public function saveS3Connection(input:S3ConnectionInput):Promise<S3ConnectionStatus> return invoke('save_s3_connection', {input: input});
  public function removeS3Connection():Promise<S3ConnectionStatus> return invoke('remove_s3_connection');
  public function testS3Connection():Promise<Bool> return invoke('test_s3_connection');
  public function getSyncStatus():Promise<SyncStatus> return invoke('get_sync_status');
  public function startSync():Promise<SyncStatus> return invoke('start_sync');
  public function cancelSync():Promise<SyncStatus> return invoke('cancel_sync');
  public function startSyncSelected(ids:Array<String>):Promise<SyncStatus> return invoke('start_sync_selected', {ids: ids});
  public function refreshRemote():Promise<RemoteRefreshResult> return invoke('refresh_remote');
  public function ensureMedia(id:String, variant:String):Promise<String> return invoke('ensure_media', {id:id, variant:variant}).then(function(path) return fileUrl(path));
  public function getCacheStatus():Promise<CacheStatus> return invoke('get_cache_status');
  public function setCacheLimit(bytes:Float):Promise<CacheStatus> return invoke('set_cache_limit', {bytes:bytes});
  public function exportOriginal(id:String, filename:String):Promise<Bool> {
    var tauri:Dynamic = Reflect.field(Browser.window, '__TAURI__');
    var dialog:Dynamic = Reflect.field(tauri, 'dialog');
    if (dialog == null) return cast Promise.reject('Save dialog unavailable');
    var save:Dynamic = Reflect.field(dialog, 'save');
    var request:Promise<Dynamic> = cast Reflect.callMethod(dialog, save, [{defaultPath:filename}]);
    return new Promise(function(resolve, reject) {
      request.then(function(path) {
        if (path == null) { resolve(false); return; }
        invoke('download_original', {id:id, destination:path}).then(function(_) resolve(true)).catchError(reject);
      }).catchError(reject);
    });
  }

  public function chooseSource():Promise<Null<String>> {
    var tauri:Dynamic = Reflect.field(Browser.window, '__TAURI__');
    var dialog:Dynamic = Reflect.field(tauri, 'dialog');
    if (dialog == null) return cast Promise.reject('Folder picker unavailable');
    return cast Reflect.callMethod(dialog, Reflect.field(dialog, 'open'), [{directory: true, multiple: false}]);
  }

  function invoke<T>(command:String, ?args:Dynamic):Promise<T> {
    var core:Dynamic = Reflect.field(Reflect.field(Browser.window, '__TAURI__'), 'core');
    return cast Reflect.callMethod(core, Reflect.field(core, 'invoke'), [command, args == null ? {} : args]);
  }

  function fileUrl(path:String):String {
    var core:Dynamic = Reflect.field(Reflect.field(Browser.window, '__TAURI__'), 'core');
    return cast Reflect.callMethod(core, Reflect.field(core, 'convertFileSrc'), [path]);
  }
}
