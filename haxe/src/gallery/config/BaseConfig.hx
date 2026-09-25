package gallery.config;


class BaseConfig implements IConfig implements DescribedType {
  @inject public var injector:IInjector;
  @inject public var logicMap:ILogicMap;
  @inject public var modelMap:IModelMap;
  @inject public var mediatorMap:IMediatorMap;

  public function configure():Void {}
}
