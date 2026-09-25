package inject.provider;

import inject.Injector;

@:keepSub
class ClassProvider implements DependencyProvider {
	var _responseType:Class<Dynamic>;

	public function new(responseType:Class<Dynamic>) {
		_responseType = responseType;
	}

	public function apply(targetType:Class<Dynamic>, activeInjector:Injector, injectParameters:Map<Dynamic, Dynamic>):Dynamic {
		return activeInjector.instantiateUnmapped(_responseType);
	}

	public function destroy():Void {}
}
