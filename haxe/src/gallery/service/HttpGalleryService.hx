package gallery.service;


class HttpGalleryService implements IGalleryService {
  public function new() {}

  public function listAssets():Promise<Array<Asset>> return request('/api/assets');
  public function importSource(?source:String):Promise<ImportResult> return request('/api/import', 'POST');
  public function getImportProgress():Promise<ImportProgress> return cast Promise.resolve({running:false,cancelling:false,processed:0,added:0,existing:0,errors:0,current:''});
  public function listImportErrors():Promise<Array<ImportError>> return cast Promise.resolve([]);
  public function cancelImport():Promise<Dynamic> return cast Promise.reject('Import cancellation requires the native app');
  public function setFavorite(id:String, favorite:Bool):Promise<Asset> {
    return request('/api/assets/' + StringTools.urlEncode(id) + '/favorite', 'POST', {favorite: favorite});
  }

  public function canChooseSource():Bool return false;
  public function chooseSource():Promise<Null<String>> return cast Promise.resolve(null);
  public function getDefaultSource():Promise<Null<String>> {
    return request('/api/settings').then(function(value:Dynamic) return cast value.source);
  }

  public function canConfigureCloud():Bool return false;
  public function supportsPhoneMedia():Bool return false;
  public function getPhoneStatus():Promise<PhoneStatus> return cast Promise.resolve({access:'unsupported',count:0});
  public function requestPhoneAccess():Promise<PhoneStatus> return getPhoneStatus();
  public function refreshPhoneMedia():Promise<PhoneRefresh> return cast Promise.resolve({access:'unsupported',found:0,added:0});
  public function getBackupPreferences():Promise<BackupPreferences> return cast Promise.resolve({autoBackup:false,wifiOnly:true,backgroundBackup:false});
  public function setBackupPreferences(preferences:BackupPreferences):Promise<BackupPreferences> return cast Promise.resolve(preferences);
  public function getS3Connection():Promise<S3ConnectionStatus> return cast Promise.reject('Cloud settings require the native app');
  public function saveS3Connection(input:S3ConnectionInput):Promise<S3ConnectionStatus> return cast Promise.reject('Cloud settings require the native app');
  public function removeS3Connection():Promise<S3ConnectionStatus> return cast Promise.reject('Cloud settings require the native app');
  public function testS3Connection():Promise<Bool> return cast Promise.reject('Cloud settings require the native app');
  public function getSyncStatus():Promise<SyncStatus> return cast Promise.reject('Photo sync requires the native app');
  public function startSync():Promise<SyncStatus> return cast Promise.reject('Photo sync requires the native app');
  public function cancelSync():Promise<SyncStatus> return cast Promise.reject('Photo sync requires the native app');
  public function startSyncSelected(ids:Array<String>):Promise<SyncStatus> return cast Promise.reject('Photo sync requires the native app');
  public function refreshRemote():Promise<RemoteRefreshResult> return cast Promise.reject('Photo sync requires the native app');
  public function ensureMedia(id:String, variant:String):Promise<String> return cast Promise.reject('Cloud photos require the native app');
  public function getCacheStatus():Promise<CacheStatus> return cast Promise.reject('Cloud cache requires the native app');
  public function setCacheLimit(bytes:Float):Promise<CacheStatus> return cast Promise.reject('Cloud cache requires the native app');
  public function exportOriginal(id:String, filename:String):Promise<Bool> return cast Promise.reject('Original export requires the native app');

  function request<T>(path:String, ?method:String = 'GET', ?body:Dynamic):Promise<T> {
    var options:Dynamic = {method: method};
    if (body != null) {
      options.headers = {'Content-Type': 'application/json'};
      options.body = haxe.Json.stringify(body);
    }
    return Browser.window.fetch(path, options).then(function(response) {
      if (!response.ok) throw 'Request failed: ' + response.status;
      return response.json();
    });
  }
}
