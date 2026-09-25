package inject.provider;

import inject.Injector;

@:keepSub
interface DependencyProvider {
	function apply(targetType:Class<Dynamic>, activeInjector:Injector, injectParameters:Map<Dynamic, Dynamic>):Dynamic;
	function destroy():Void;
}
