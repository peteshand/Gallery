package eva;

import polyfill.events.EventDispatcher;
import inject.utils.UID;
import eva.IContext;
import eva.IInjector;
import eva.IMatcher;
import eva.LifecycleEvent;
import eva.IExtension.IExtension_Or_Class;
import eva.IConfig.IConfig_Or_Class;
import haxe.macro.Expr;
import haxe.macro.TypeTools;
import haxe.macro.Context as MacroContext;
import haxe.macro.Compiler;

#if macro
using haxe.macro.Tools;
#end

@:keepSub
class Context extends EventDispatcher implements IContext {
	macro public static function install1(value:haxe.macro.Expr):haxe.macro.Expr {
		var path = value.toString();
		var func:String = "var _" + path.split(".").join("_") + " = " + path + ";";
		trace(func);
		return untyped MacroContext.parse(func, MacroContext.currentPos());
	}

	macro public function install2(value:haxe.macro.Expr):haxe.macro.Expr {
		var path = value.toString();
		var func:String = "var _" + path.split(".").join("_") + " = " + path + ";";
		trace(func);
		return untyped MacroContext.parse(func, MacroContext.currentPos());
	}

	var _injector:IInjector = new Injector();

	public var injector(get, null):IInjector;
	public var state(get, null):String;
	public var uninitialized(get, null):Bool;
	public var initialized(get, null):Bool;
	public var active(get, null):Bool;
	public var suspended(get, null):Bool;
	public var destroyed(get, null):Bool;

	function get_injector():IInjector {
		return _injector;
	}

	function get_state():String {
		return _lifecycle.state;
	}

	function get_uninitialized():Bool {
		return _lifecycle.uninitialized;
	}

	function get_initialized():Bool {
		return _lifecycle.initialized;
	}

	function get_active():Bool {
		return _lifecycle.active;
	}

	function get_suspended():Bool {
		return _lifecycle.suspended;
	}

	function get_destroyed():Bool {
		return _lifecycle.destroyed;
	}

	var _uid:String = UID.create(Context);
	var _children:Array<Dynamic> = [];
	var _pin:Pin;
	var _lifecycle:Lifecycle;
	var _configManager:ConfigManager;
	var _extensionInstaller:ExtensionInstaller;

	public function new() {
		setup();
		super();
	}

	public inline function initialize(callback:Void->Void = null):Void {
		_lifecycle.initialize(callback);
	}

	public inline function suspend(callback:Void->Void = null):Void {
		_lifecycle.suspend(callback);
	}

	public inline function resume(callback:Void->Void = null):Void {
		_lifecycle.resume(callback);
	}

	public inline function destroy(callback:Void->Void = null):Void {
		_lifecycle.destroy(callback);
	}

	public inline function beforeInitializing(handler:Void->Void):IContext {
		_lifecycle.beforeInitializing(handler);
		return this;
	}

	public inline function whenInitializing(handler:Void->Void):IContext {
		_lifecycle.whenInitializing(handler);
		return this;
	}

	public inline function afterInitializing(handler:Void->Void):IContext {
		_lifecycle.afterInitializing(handler);
		return this;
	}

	public inline function beforeSuspending(handler:Void->Void):IContext {
		_lifecycle.beforeSuspending(handler);
		return this;
	}

	public inline function whenSuspending(handler:Void->Void):IContext {
		_lifecycle.whenSuspending(handler);
		return this;
	}

	public inline function afterSuspending(handler:Void->Void):IContext {
		_lifecycle.afterSuspending(handler);
		return this;
	}

	public inline function beforeResuming(handler:Void->Void):IContext {
		_lifecycle.beforeResuming(handler);
		return this;
	}

	public inline function whenResuming(handler:Void->Void):IContext {
		_lifecycle.whenResuming(handler);
		return this;
	}

	public inline function afterResuming(handler:Void->Void):IContext {
		_lifecycle.afterResuming(handler);
		return this;
	}

	public inline function beforeDestroying(handler:Void->Void):IContext {
		_lifecycle.beforeDestroying(handler);
		return this;
	}

	public inline function whenDestroying(handler:Void->Void):IContext {
		_lifecycle.whenDestroying(handler);
		return this;
	}

	public inline function afterDestroying(handler:Void->Void):IContext {
		_lifecycle.afterDestroying(handler);
		return this;
	}

	public function install(ext1:IExtension_Or_Class, ?ext2:IExtension_Or_Class, ?ext3:IExtension_Or_Class, ?ext4:IExtension_Or_Class,
			?ext5:IExtension_Or_Class, ?ext6:IExtension_Or_Class, ?ext7:IExtension_Or_Class, ?ext8:IExtension_Or_Class, ?ext9:IExtension_Or_Class,
			?ext10:IExtension_Or_Class):IContext {
		_extensionInstaller.install(ext1);
		_extensionInstaller.install(ext2);
		_extensionInstaller.install(ext3);
		_extensionInstaller.install(ext4);
		_extensionInstaller.install(ext5);
		_extensionInstaller.install(ext6);
		_extensionInstaller.install(ext7);
		_extensionInstaller.install(ext8);
		_extensionInstaller.install(ext9);
		_extensionInstaller.install(ext10);
		return this;
	}

	public function configure(config1:IConfig_Or_Class, ?config2:IConfig_Or_Class, ?config3:IConfig_Or_Class, ?config4:IConfig_Or_Class,
			?config5:IConfig_Or_Class, ?config6:IConfig_Or_Class, ?config7:IConfig_Or_Class, ?config8:IConfig_Or_Class, ?config9:IConfig_Or_Class,
			?config10:IConfig_Or_Class):IContext {
		_configManager.addConfig(config1);
		_configManager.addConfig(config2);
		_configManager.addConfig(config3);
		_configManager.addConfig(config4);
		_configManager.addConfig(config5);
		_configManager.addConfig(config6);
		_configManager.addConfig(config7);
		_configManager.addConfig(config8);
		_configManager.addConfig(config9);
		_configManager.addConfig(config10);
		return this;
	}

	public function addChild(child:IContext):IContext {
		if (_children.indexOf(child) == -1) {
			trace("Adding child context {0}", [child]);
			if (child.uninitialized) {
				trace("Child context {0} must be uninitialized", [child]);
			}
			if (child.injector.parent != null) {
				trace("Child context {0} must not have a parent Injector", [child]);
			}
			_children.push(child);
			child.injector.parent = injector;
			child.addEventListener(LifecycleEvent.POST_DESTROY, onChildDestroy);
		}
		return this;
	}

	public function removeChild(child:IContext):IContext {
		var childIndex:Int = _children.indexOf(child);
		if (childIndex > -1) {
			trace("Removing child context {0}", [child]);
			_children.splice(childIndex, 1);
			child.injector.parent = null;
			child.removeEventListener(LifecycleEvent.POST_DESTROY, onChildDestroy);
		} else {
			trace("Child context {0} must be a child of {1}", [child, this]);
		}
		return this;
	}

	public function addConfigHandler(matcher:IMatcher, handler:Dynamic):IContext {
		_configManager.addConfigHandler(matcher, handler);
		return this;
	}

	public function detain(instances:Dynamic):IContext {
		if (Std.isOfType(instances, Array)) {
			var instancesArray:Array<Dynamic> = cast(instances);
			for (instance in instancesArray) {
				_pin.detain(instance);
			}
		} else {
			_pin.detain(instances);
		}
		return this;
	}

	public function release(instances:Dynamic):IContext {
		if (Std.isOfType(instances, Array)) {
			var instancesArray:Array<Dynamic> = cast(instances);
			for (instance in instancesArray) {
				_pin.release(instance);
			}
		} else {
			_pin.release(instances);
		}
		return this;
	}

	override public function toString():String {
		return _uid;
	}

	function setup():Void {
		_injector.map(IInjector).toValue(_injector);
		_injector.map(IContext).toValue(this);
		_pin = new Pin(this);
		_lifecycle = new Lifecycle(this);
		_configManager = new ConfigManager(this);
		_extensionInstaller = new ExtensionInstaller(this);
		beforeInitializing(beforeInitializingCallback);
		afterInitializing(afterInitializingCallback);
		beforeDestroying(beforeDestroyingCallback);
		afterDestroying(afterDestroyingCallback);
	}

	function beforeInitializingCallback():Void {
		//
	}

	function afterInitializingCallback():Void {
		//
	}

	function beforeDestroyingCallback():Void {
		//
	}

	function afterDestroyingCallback():Void {
		_extensionInstaller.destroy();
		_configManager.destroy();
		_pin.releaseAll();
		_injector.teardown();
		removeChildren();
	}

	function onChildDestroy(event:LifecycleEvent):Void {
		removeChild(cast(event.target, IContext));
	}

	function removeChildren():Void {
		for (child in _children) {
			removeChild(child);
		}
		_children = [];
	}
}
