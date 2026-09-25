package inject.provider;

import inject.Injector;

@:keepSub
class InjectorUsingProvider extends ForwardingProvider {
	public var injector:Injector;

	public function new(injector:Injector, provider:DependencyProvider) {
		super(provider);
		this.injector = injector;
	}

	override public function apply(targetType:Class<Dynamic>, activeInjector:Injector, injectParameters:Map<Dynamic, Dynamic>):Dynamic {
		return provider.apply(targetType, injector, injectParameters);
	}
}
