package gallery.model;


class CloudModel {
  public var available = new Notifier<Bool>(false);
  public var connection = new Notifier<Null<S3ConnectionStatus>>(null);
  public var progress = new Notifier<Null<SyncStatus>>(null);
  public var message = new Notifier<String>('');
  public var busy = new Notifier<Bool>(false);
  public var cache = new Notifier<Null<CacheStatus>>(null);
  public var catalogBusy = new Notifier<Bool>(false);
  public var refreshRequested = new Signal();
  public var saveRequested = new Signal1<S3ConnectionInput>();
  public var removeRequested = new Signal();
  public var testRequested = new Signal();
  public var syncRequested = new Signal();
  public var syncSelectedRequested = new Signal1<Array<String>>();
  public var selectedSyncStarted = new Signal();
  public var catalogRefreshRequested = new Signal();
  public var cacheRefreshRequested = new Signal();
  public var cacheLimitRequested = new Signal1<Float>();

  public function new() {}
}
