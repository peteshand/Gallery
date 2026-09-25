package gallery.config;


class ServiceConfig extends BaseConfig {
  override public function configure():Void {
    if (TauriGalleryService.isAvailable()) injector.map(IGalleryService).toSingleton(TauriGalleryService);
    else injector.map(IGalleryService).toSingleton(HttpGalleryService);
  }
}
