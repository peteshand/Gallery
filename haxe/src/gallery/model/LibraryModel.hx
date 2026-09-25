package gallery.model;


class LibraryModel {
  public var assets = new Notifier<Array<Asset>>([]);
  public var loading = new Notifier<Bool>(false);
  public var error = new Notifier<String>(null);
  public var status = new Notifier<String>('');
  public var importProgress = new Notifier<Null<ImportProgress>>(null);
  public var importErrors = new Notifier<Array<ImportError>>([]);
  public var importErrorsRequested = new Signal();
  public var importRequested = new Signal1<Null<String>>();
  public var favoriteRequested = new Signal1<Asset>();
  public var refreshRequested = new Signal();
  public var cancelImportRequested = new Signal();

  public function new() {}
}
