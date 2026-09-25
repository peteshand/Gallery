package inject.def;

import inject.Injector;
import inject.provider.DependencyProvider;

@:keepSub
class PropertyInjectionPoint extends InjectionPoint {
	var _propertyName:String;
	var _mappingId:String;
	var _optional:Bool;

	public function new(mappingId:String, propertyName:String, optional:Bool, injectParameters:Map<Dynamic, Dynamic>) {
		_propertyName = propertyName;
		_mappingId = mappingId;
		_optional = optional;
		this.injectParameters = injectParameters;
		super();
	}

	override public function applyInjection(target:Dynamic, targetType:Class<Dynamic>, injector:Injector):Void {
		var provider:DependencyProvider = injector.getProvider(_mappingId);
		if (provider == null) {
			if (_optional) {
				return;
			}

			var targetStr:String;
			#if js
			targetStr = Type.getClassName(Type.getClass(target)); // Calling toString in JS can go recursive
			#else
			targetStr = Std.string(target);
			#end

			throw('Injector is missing a mapping to handle injection into property "'
				+ _propertyName
				+ '" of object "'
				+ targetStr
				+ '" with type "'
				+ Type.getClassName(targetType)
				+ '". Target dependency: "'
				+ _mappingId
				+ '"');
		}
		Reflect.setProperty(target, _propertyName, provider.apply(targetType, injector, injectParameters));
	}
}
