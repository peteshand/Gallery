package gallery.model;


class GalleryModel {
  public var tab = new Notifier<String>('Photos');
  public var query = new Notifier<String>('');
  public var selectedIds = new Notifier<Array<String>>([]);
  public var selectionAnchor = new Notifier<String>('');
  public var activePhotoId = new Notifier<String>(null);
  public var settingsOpen = new Notifier<Bool>(false);
  public var detailsOpen = new Notifier<Bool>(false);
  public var collection = new Notifier<String>(null);
  public var sourcePath = new Notifier<String>(null);
  public var canChooseSource = new Notifier<Bool>(false);
  public var cloudOnlyDevice = new Notifier<Bool>(false);
  public var gridDensity = new Notifier<Int>(0);
  public var gridPinching = new Notifier<Bool>(false);
  public var chooseSourceRequested = new Signal();
  public var dragClickSuppressedUntil = new Notifier<Float>(0);
  public var dragRequested = new Signal1<{id:String, pointerId:Int, x:Float, y:Float, immediate:Bool}>();

  public function new() {}
}
