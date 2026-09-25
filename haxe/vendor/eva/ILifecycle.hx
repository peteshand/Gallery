package eva;

import polyfill.events.IEventDispatcher;

@:keepSub
interface ILifecycle extends IEventDispatcher {
	var state(default, null):String;
	var target(default, null):Dynamic;
	var uninitialized(get, null):Bool;
	var initialized(get, null):Bool;
	var active(get, null):Bool;
	var suspended(get, null):Bool;
	var destroyed(get, null):Bool;
	function initialize(callback:Void->Void = null):Void;
	function suspend(callback:Void->Void = null):Void;
	function resume(callback:Void->Void = null):Void;
	function destroy(callback:Void->Void = null):Void;
	function beforeInitializing(handler:Void->Void):ILifecycle;
	function whenInitializing(handler:Void->Void):ILifecycle;
	function afterInitializing(handler:Void->Void):ILifecycle;
	function beforeSuspending(handler:Void->Void):ILifecycle;
	function whenSuspending(handler:Void->Void):ILifecycle;
	function afterSuspending(handler:Void->Void):ILifecycle;
	function beforeResuming(handler:Void->Void):ILifecycle;
	function whenResuming(handler:Void->Void):ILifecycle;
	function afterResuming(handler:Void->Void):ILifecycle;
	function beforeDestroying(handler:Void->Void):ILifecycle;
	function whenDestroying(handler:Void->Void):ILifecycle;
	function afterDestroying(handler:Void->Void):ILifecycle;
}
