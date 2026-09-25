package gallery.model;


typedef MediaRequest = { var id:String; var variant:String; }

class MediaModel {
  public var paths = new Notifier<Map<String, String>>(new Map());
  public var thumbnailOnly = new Notifier<Bool>(false);
  public var error = new Notifier<String>('');
  public var exportMessage = new Notifier<String>('');
  public var requested = new Signal1<MediaRequest>();
  public var exportRequested = new Signal1<Asset>();

  public function new() {}
}
