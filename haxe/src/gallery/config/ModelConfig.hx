package gallery.config;


class ModelConfig extends BaseConfig {
  override public function configure():Void {
    modelMap.map(LibraryModel).asSingleton();
    modelMap.map(GalleryModel).asSingleton();
    modelMap.map(CloudModel).asSingleton();
    modelMap.map(MediaModel).asSingleton();
    modelMap.map(PhoneModel).asSingleton();
  }
}
