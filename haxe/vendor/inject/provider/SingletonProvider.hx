package inject.provider;

import inject.Injector;

@:keepSub
class SingletonProvider implements DependencyProvider {
	var _responseType:Class<Dynamic>;
	var _creatingInjector:Injector;
	var _response:Dynamic;
	var _destroyed:Bool;

	public function new(responseType:Class<Dynamic>, creatingInjector:Injector) {
		_responseType = responseType;
		_creatingInjector = creatingInjector;
	}

	public function apply(targetType:Class<Dynamic>, activeInjector:Injector, injectParameters:Map<Dynamic, Dynamic>):Dynamic {
		if (_response == null) {
			_response = createResponse(_creatingInjector);
		}
		return _response;
	}

	function createResponse(injector:Injector):Dynamic {
		if (_destroyed) {
			throw "Forbidden usage of unmapped singleton provider for type " + Type.getClassName(_responseType);
		}
		return injector.instantiateUnmapped(_responseType);
	}

	public function destroy():Void {
		_destroyed = true;
		if (_response != null && _creatingInjector != null && _creatingInjector.hasManagedInstance(_response)) {
			_creatingInjector.destroyInstance(_response);
		}
		_creatingInjector = null;
		_response = null;
	}
}
