package gallery.config;


class LogicConfig extends BaseConfig {
  override public function configure():Void {
    logicMap.map(LibraryLogic);
    logicMap.map(CloudLogic);
    logicMap.map(SourceLogic);
    logicMap.map(MediaLogic);
    logicMap.map(PhoneLogic);
  }
}
