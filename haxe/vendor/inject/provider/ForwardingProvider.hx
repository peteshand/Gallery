package inject.provider;

import inject.Injector;

@:keepSub
class ForwardingProvider implements DependencyProvider {
	public var provider:DependencyProvider;

	public function new(provider:DependencyProvider) {
		this.provider = provider;
	}

	public function apply(targetType:Class<Dynamic>, activeInjector:Injector, injectParameters:Map<Dynamic, Dynamic>):Dynamic {
		return provider.apply(targetType, activeInjector, injectParameters);
	}

	public function destroy():Void {
		provider.destroy();
	}
}
