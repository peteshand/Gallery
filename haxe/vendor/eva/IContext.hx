package eva;

import polyfill.events.IEventDispatcher;
import eva.IExtension.IExtension_Or_Class;
import eva.IConfig.IConfig_Or_Class;

interface IContext extends IEventDispatcher {
	public var injector(get, null):IInjector;
	public var state(get, null):String;
	public var uninitialized(get, null):Bool;
	public var initialized(get, null):Bool;
	public var active(get, null):Bool;
	public var suspended(get, null):Bool;
	public var destroyed(get, null):Bool;

	function install(ext1:IExtension_Or_Class, ?ext2:IExtension_Or_Class, ?ext3:IExtension_Or_Class, ?ext4:IExtension_Or_Class, ?ext5:IExtension_Or_Class,
		?ext6:IExtension_Or_Class, ?ext7:IExtension_Or_Class, ?ext8:IExtension_Or_Class, ?ext9:IExtension_Or_Class, ?ext10:IExtension_Or_Class):IContext;

	function configure(config1:IConfig_Or_Class, ?config2:IConfig_Or_Class, ?config3:IConfig_Or_Class, ?config4:IConfig_Or_Class, ?config5:IConfig_Or_Class,
		?config6:IConfig_Or_Class, ?config7:IConfig_Or_Class, ?config8:IConfig_Or_Class, ?config9:IConfig_Or_Class, ?config10:IConfig_Or_Class):IContext;

	function addChild(child:IContext):IContext;
	function removeChild(child:IContext):IContext;
	function addConfigHandler(matcher:IMatcher, handler:Dynamic):IContext;
	function detain(instances:Dynamic):IContext;
	function release(instances:Dynamic):IContext;
	function initialize(callback:Void->Void = null):Void;
	function suspend(callback:Void->Void = null):Void;
	function resume(callback:Void->Void = null):Void;
	function destroy(callback:Void->Void = null):Void;
	function beforeInitializing(handler:Void->Void):IContext;
	function whenInitializing(handler:Void->Void):IContext;
	function afterInitializing(handler:Void->Void):IContext;
	function beforeSuspending(handler:Void->Void):IContext;
	function whenSuspending(handler:Void->Void):IContext;
	function afterSuspending(handler:Void->Void):IContext;
	function beforeResuming(handler:Void->Void):IContext;
	function whenResuming(handler:Void->Void):IContext;
	function afterResuming(handler:Void->Void):IContext;
	function beforeDestroying(handler:Void->Void):IContext;
	function whenDestroying(handler:Void->Void):IContext;
	function afterDestroying(handler:Void->Void):IContext;
}
