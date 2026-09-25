package inject.provider;

import inject.Injector;

@:keepSub
class FactoryProvider implements DependencyProvider {
	private var _factoryClass:Class<Dynamic>;

	public function new(factoryClass:Class<Dynamic>) {
		_factoryClass = factoryClass;
	}

	public function apply(targetType:Class<Dynamic>, activeInjector:Injector, injectParameters:Map<Dynamic, Dynamic>):Dynamic {
		var dependencyProvider:DependencyProvider = cast(activeInjector.getInstance(_factoryClass));
		return dependencyProvider.apply(targetType, activeInjector, injectParameters);
	}

	public function destroy():Void {}
}
