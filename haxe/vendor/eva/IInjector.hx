package eva;

import polyfill.events.IEventDispatcher;
import polyfill.system.ApplicationDomain;
import inject.provider.FallbackDependencyProvider;
import inject.mapping.InjectionMapping;
import inject.def.TypeDescription;

@:keepSub
interface IInjector extends IEventDispatcher {
	public var parent(get, set):IInjector;
	@:isVar public var applicationDomain(get, set):Null<ApplicationDomain>;
	public var fallbackProvider(get, set):FallbackDependencyProvider;
	public var blockParentFallbackProvider(get, set):Bool;

	function addTypeDescription(type:Class<Dynamic>, description:TypeDescription):Void;
	function getTypeDescription(type:Class<Dynamic>):TypeDescription;
	function hasMapping(type:Class<Dynamic>, name:String = ''):Bool;
	function hasDirectMapping(type:Class<Dynamic>, name:String = ''):Bool;
	function map(type:Class<Dynamic>, name:String = ''):InjectionMapping;
	function unmap(type:Class<Dynamic>, name:String = ''):Void;
	function satisfies(type:Class<Dynamic>, name:String = ''):Bool;
	function satisfiesDirectly(type:Class<Dynamic>, name:String = ''):Bool;
	function getMapping(type:Class<Dynamic>, name:String = ''):InjectionMapping;
	function injectInto(target:Dynamic):Void;
	function getInstance(type:Class<Dynamic>, name:String = '', targetType:Class<Dynamic> = null):Dynamic;
	function getOrCreateNewInstance(type:Class<Dynamic>):Dynamic;
	function instantiateUnmapped(type:Class<Dynamic>):Dynamic;
	function destroyInstance(instance:Dynamic):Void;
	function teardown():Void;
	function createChild(applicationDomain:ApplicationDomain = null):IInjector;
}
