package eva.ext.config;

import eva.IContext;
import eva.IExtension;
import eva.IInjector;
import eva.ext.config.IConfigModel;
import eva.ext.matching.InstanceOfType;

/**
 * ...
 * @author P.J.Shand
 */
class ConfigExtension implements IExtension {
	var injector:IInjector;

	public function new() {}

	public function extend(context:IContext):Void {
		injector = context.injector;
		context.addConfigHandler(InstanceOfType.call(IConfigModel), handleIConfigModel);
	}

	function handleIConfigModel(configModel:IConfigModel):Void {
		var ConfigClass:Class<Dynamic> = Type.getClass(configModel);
		injector.map(IConfigModel).toValue(configModel);
		injector.map(ConfigClass).toValue(configModel);

		#if html5
		map(QueryStringLogic);
		#end
	}

	function map(type:Class<Initializable>) {
		injector.map(type).asSingleton();
		var instance:Initializable = injector.getInstance(type);

		instance.initialize();
	}
}

typedef Initializable = {
	public function initialize():Void;
}
