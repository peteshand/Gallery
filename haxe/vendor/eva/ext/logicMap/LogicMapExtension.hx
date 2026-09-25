package eva.ext.logicMap;

import eva.ext.logicMap.api.ILogicMap;
import eva.ext.logicMap.impl.LogicMap;
import eva.IContext;
import eva.IExtension;
import eva.IInjector;

/**
 * ...
 * @author P.J.Shand
 */
class LogicMapExtension implements IExtension {
	private var _injector:IInjector;

	// private var logicMap:ILogicMap;

	public function new() {}

	public function extend(context:IContext):Void {
		// context.beforeInitializing(beforeInitializing);
		_injector = context.injector;
		_injector.map(ILogicMap).toSingleton(LogicMap);
	}

	// function beforeInitializing()
	// {
	// logicMap = _injector.getInstance(ILogicMap);
	// }
}
