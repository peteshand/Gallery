package eva.ext.logicMap.impl;

import inject.utils.DescribedType;
import eva.ext.logicMap.api.ILogic;
import eva.ext.logicMap.api.ILogicMap;
import eva.IContext;
import eva.IInjector;
import haxe.extern.EitherType;

/**
 * ...
 * @author P.J.Shand
 */
class LogicMap implements ILogicMap implements DescribedType {
	@inject public var injector:IInjector;
	var instances:Array<ILogic>;

	public function new(context:IContext) {
		instances = [];
		context.beforeDestroying(dispose);
	}

	public function map(type:Class<ILogic>, initialize:EitherType<Bool, EitherType<SignalA, SignalB>> = true):ILogic {
		injector.map(type).asSingleton();

		var instance:ILogic = injector.getInstance(type);
		if (instances.indexOf(instance) == -1) instances.push(instance);

		if (Std.isOfType(initialize, Bool)) {
			if (initialize == true)
				instance.initialize();
		} else {
			var add = Reflect.getProperty(initialize, 'add');
			Reflect.callMethod(initialize, add, [
				() -> {
					instance.initialize();
				}
			]);
		}

		return instance;
	}

	function dispose():Void {
		for (instance in instances) {
			try instance.dispose() catch (error:Dynamic) trace(error);
		}
		instances = [];
	}
}

typedef SignalA = {
	function dispatch():Void;
	function add(callback:Void->Void):Void;
}

typedef SignalB = {
	function dispatch():Void;
	function add(callback:Void->Void, ?fireOnce:Bool, ?priority:Int, ?fireOnAdd:Null<Bool>):Void;
}
