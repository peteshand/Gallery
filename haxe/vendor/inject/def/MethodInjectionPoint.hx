package inject.def;

import inject.Injector;
import inject.provider.DependencyProvider;

@:keepSub
class MethodInjectionPoint extends InjectionPoint {
	var _parameterMappingIDs:Array<String>;
	var _requiredParameters:Int;
	var _isOptional:Bool;
	var _methodName:String;

	public function new(methodName:String, parameters:Array<String>, requiredParameters:UInt, isOptional:Bool, injectParameters:Map<Dynamic, Dynamic>) {
		_methodName = methodName;
		_parameterMappingIDs = parameters;
		_requiredParameters = requiredParameters;
		_isOptional = isOptional;
		this.injectParameters = injectParameters;
		super();
	}

	override public function applyInjection(target:Dynamic, targetType:Class<Dynamic>, injector:Injector):Void {
		var p:Array<Dynamic> = gatherParameterValues(target, targetType, injector);

		if (p.length >= _requiredParameters) {
			var func = Reflect.getProperty(target, _methodName);
			if (Reflect.isFunction(func)) {
				Reflect.callMethod(target, func, p);
			}
		}
		p = [];
	}

	function gatherParameterValues(target:Dynamic, targetType:Class<Dynamic>, injector:Injector):Array<Dynamic> {
		var length:Int = _parameterMappingIDs.length;
		var parameters:Array<Dynamic> = [];

		for (i in 0...length) {
			var parameterMappingId:String = _parameterMappingIDs[i];
			var provider:DependencyProvider = injector.getProvider(parameterMappingId);
			if (provider == null) {
				if (i >= _requiredParameters || _isOptional) {
					break;
				}

				var errorMsg:String = 'Injector is missing a mapping to handle injection into target "';
				errorMsg += target;
				errorMsg += '" of type "';
				errorMsg += Type.getClassName(targetType);
				errorMsg += '". Target dependency: ';
				errorMsg += parameterMappingId;
				errorMsg += ', method: ';
				errorMsg += _methodName;
				errorMsg += ', parameter: ';
				errorMsg += (i + 1);

				throw errorMsg;
			}

			parameters[i] = provider.apply(targetType, injector, injectParameters);
		}
		return parameters;
	}
}
