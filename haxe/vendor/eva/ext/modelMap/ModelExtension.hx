package eva.ext.modelMap;

import eva.ext.modelMap.api.IModelMap;
import eva.ext.modelMap.impl.ModelMap;
import eva.ext.matching.InstanceOfType;
import eva.IContext;
import eva.IExtension;
import eva.IInjector;
import inject.InjectionEvent;

/**
 * ...
 * @author P.J.Shand
 */
class ModelExtension implements IExtension {
	private var _injector:IInjector;

	public function new() {}

	public function extend(context:IContext):Void {
		_injector = context.injector;
		_injector.map(IModelMap).toSingleton(ModelMap);
	}
}
