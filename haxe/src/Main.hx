package;


class Main {
  static var context:IContext;

  public static function main():Void {
    context = new Context();
    context.install(DomBundle);
    context.install(ModelExtension);
    context.configure(ModelConfig, ServiceConfig, LogicConfig, ViewConfig);
    context.initialize();
  }
}
