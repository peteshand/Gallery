package inject.provider;

import inject.mapping.InjectionMapping;
import inject.Injector;

@:keepSub
class OtherMappingProvider implements DependencyProvider {
	var _mapping:InjectionMapping;

	public function new(mapping:InjectionMapping) {
		_mapping = mapping;
	}

	public function apply(targetType:Class<Dynamic>, activeInjector:Injector, injectParameters:Map<Dynamic, Dynamic>):Dynamic {
		return _mapping.getProvider().apply(targetType, activeInjector, injectParameters);
	}

	public function destroy():Void {}
}
