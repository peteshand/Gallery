package gallery.config;


class ViewConfig extends BaseConfig {
  @inject public var domViewMap:IDomViewMap;

  override public function configure():Void {
    mediatorMap.map(GalleryView).toMediator(GalleryViewMediator);
    domViewMap.addView(new GalleryView());
  }
}
