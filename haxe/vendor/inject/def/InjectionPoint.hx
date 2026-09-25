package inject.def;

import inject.Injector;

@:keepSub
class InjectionPoint {
	public var next:InjectionPoint;
	public var last:InjectionPoint;
	public var injectParameters:Map<Dynamic, Dynamic>;

	public function new() {}

	public function applyInjection(target:Dynamic, targetType:Class<Dynamic>, injector:Injector):Void {}
}
