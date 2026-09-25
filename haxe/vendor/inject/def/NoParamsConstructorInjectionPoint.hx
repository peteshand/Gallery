package inject.def;

import inject.Injector;

@:keepSub
class NoParamsConstructorInjectionPoint extends ConstructorInjectionPoint {
	public function new() {
		super([], 0, injectParameters);
	}

	override public function createInstance(type:Class<Dynamic>, injector:Injector):Dynamic {
		return Type.createInstance(type, []);
	}
}
