package gallery.model;

class PhoneModel {
  public var supported = new Notifier<Bool>(false);
  public var status = new Notifier<Null<PhoneStatus>>(null);
  public var busy = new Notifier<Bool>(false);
  public var message = new Notifier<String>('');
  public var preferences = new Notifier<Null<BackupPreferences>>(null);
  public var accessRequested = new Signal();
  public var refreshRequested = new Signal();
  public var preferencesRequested = new Signal1<BackupPreferences>();
  public function new() {}
}
