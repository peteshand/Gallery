package inject.provider;

import inject.Injector;

@:keepSub
class ValueProvider implements DependencyProvider {
	var _value:Dynamic;
	var _creatingInjector:Injector;

	public function new(value:Dynamic, creatingInjector:Injector = null) {
		_value = value;
		_creatingInjector = creatingInjector;
	}

	public function apply(targetType:Class<Dynamic>, activeInjector:Injector, injectParameters:Map<Dynamic, Dynamic>):Dynamic {
		return _value;
	}

	public function destroy():Void {
		if (_value != null && _creatingInjector != null && _creatingInjector.hasManagedInstance(_value)) {
			_creatingInjector.destroyInstance(_value);
		}
		_creatingInjector = null;
		_value = null;
	}
}
