package gallery.service;


interface IGalleryService {
  function listAssets():Promise<Array<Asset>>;
  function importSource(?source:String):Promise<ImportResult>;
  function getImportProgress():Promise<ImportProgress>;
  function listImportErrors():Promise<Array<ImportError>>;
  function cancelImport():Promise<Dynamic>;
  function setFavorite(id:String, favorite:Bool):Promise<Asset>;
  function canChooseSource():Bool;
  function chooseSource():Promise<Null<String>>;
  function getDefaultSource():Promise<Null<String>>;
  function canConfigureCloud():Bool;
  function getS3Connection():Promise<S3ConnectionStatus>;
  function saveS3Connection(input:S3ConnectionInput):Promise<S3ConnectionStatus>;
  function removeS3Connection():Promise<S3ConnectionStatus>;
  function testS3Connection():Promise<Bool>;
  function getSyncStatus():Promise<SyncStatus>;
  function startSync():Promise<SyncStatus>;
  function cancelSync():Promise<SyncStatus>;
  function startSyncSelected(ids:Array<String>):Promise<SyncStatus>;
  function refreshRemote():Promise<RemoteRefreshResult>;
  function ensureMedia(id:String, variant:String):Promise<String>;
  function getCacheStatus():Promise<CacheStatus>;
  function setCacheLimit(bytes:Float):Promise<CacheStatus>;
  function exportOriginal(id:String, filename:String):Promise<Bool>;
  function supportsPhoneMedia():Bool;
  function getPhoneStatus():Promise<PhoneStatus>;
  function requestPhoneAccess():Promise<PhoneStatus>;
  function refreshPhoneMedia():Promise<PhoneRefresh>;
  function getBackupPreferences():Promise<BackupPreferences>;
  function setBackupPreferences(preferences:BackupPreferences):Promise<BackupPreferences>;
}
