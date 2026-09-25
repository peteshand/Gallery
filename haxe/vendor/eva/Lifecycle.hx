package eva;

import polyfill.events.Event;
import polyfill.events.EventDispatcher;
import polyfill.events.IEventDispatcher;
import eva.ILifecycle;
import eva.LifecycleError;
import eva.LifecycleEvent;
import eva.LifecycleState;

@:keepSub
class Lifecycle implements ILifecycle {
	public var state(default, null):String = LifecycleState.UNINITIALIZED;
	public var target(default, null):Dynamic;
	public var uninitialized(get, null):Bool;
	public var initialized(get, null):Bool;
	public var active(get, null):Bool;
	public var suspended(get, null):Bool;
	public var destroyed(get, null):Bool;

	function get_uninitialized():Bool {
		return state == LifecycleState.UNINITIALIZED;
	}

	function get_initialized():Bool {
		return state != LifecycleState.UNINITIALIZED && state != LifecycleState.INITIALIZING;
	}

	function get_active():Bool {
		return state == LifecycleState.ACTIVE;
	}

	function get_suspended():Bool {
		return state == LifecycleState.SUSPENDED;
	}

	public function get_destroyed():Bool {
		return state == LifecycleState.DESTROYED;
	}

	var _reversedEventTypes = new Map<String, Dynamic>();
	var _reversePriority:Int = 0;
	var _initialize:LifecycleTransition;
	var _suspend:LifecycleTransition;
	var _resume:LifecycleTransition;
	var _destroy:LifecycleTransition;
	var _dispatcher:IEventDispatcher;

	public function new(target:Dynamic) {
		this.target = target;
		if (Std.isOfType(target, IEventDispatcher))
			_dispatcher = cast(target, IEventDispatcher);
		else
			_dispatcher = new EventDispatcher(this);
		configureTransitions();
	}

	public inline function initialize(callback:Void->Void = null):Void {
		_initialize.enter(callback);
	}

	public inline function suspend(callback:Void->Void = null):Void {
		_suspend.enter(callback);
	}

	public inline function resume(callback:Void->Void = null):Void {
		_resume.enter(callback);
	}

	public inline function destroy(callback:Void->Void = null):Void {
		_destroy.enter(callback);
	}

	public inline function beforeInitializing(handler:Dynamic):ILifecycle {
		if (!uninitialized)
			reportError(LifecycleError.LATE_HANDLER_ERROR_MESSAGE);
		_initialize.addBeforeHandler(handler);
		return this;
	}

	public inline function whenInitializing(handler:Dynamic):ILifecycle {
		if (initialized)
			reportError(LifecycleError.LATE_HANDLER_ERROR_MESSAGE);
		addEventListener(LifecycleEvent.INITIALIZE, createSyncLifecycleListener(handler, true));
		return this;
	}

	public inline function afterInitializing(handler:Dynamic):ILifecycle {
		if (initialized)
			reportError(LifecycleError.LATE_HANDLER_ERROR_MESSAGE);
		addEventListener(LifecycleEvent.POST_INITIALIZE, createSyncLifecycleListener(handler, true));
		return this;
	}

	public inline function beforeSuspending(handler:Dynamic):ILifecycle {
		_suspend.addBeforeHandler(handler);
		return this;
	}

	public inline function whenSuspending(handler:Dynamic):ILifecycle {
		addEventListener(LifecycleEvent.SUSPEND, createSyncLifecycleListener(handler));
		return this;
	}

	public inline function afterSuspending(handler:Dynamic):ILifecycle {
		addEventListener(LifecycleEvent.POST_SUSPEND, createSyncLifecycleListener(handler));
		return this;
	}

	public inline function beforeResuming(handler:Dynamic):ILifecycle {
		_resume.addBeforeHandler(handler);
		return this;
	}

	public inline function whenResuming(handler:Dynamic):ILifecycle {
		addEventListener(LifecycleEvent.RESUME, createSyncLifecycleListener(handler));
		return this;
	}

	public inline function afterResuming(handler:Dynamic):ILifecycle {
		addEventListener(LifecycleEvent.POST_RESUME, createSyncLifecycleListener(handler));
		return this;
	}

	public inline function beforeDestroying(handler:Dynamic):ILifecycle {
		_destroy.addBeforeHandler(handler);
		return this;
	}

	public inline function whenDestroying(handler:Dynamic):ILifecycle {
		addEventListener(LifecycleEvent.DESTROY, createSyncLifecycleListener(handler, true));
		return this;
	}

	public inline function afterDestroying(handler:Dynamic):ILifecycle {
		addEventListener(LifecycleEvent.POST_DESTROY, createSyncLifecycleListener(handler, true));
		return this;
	}

	public inline function addEventListener(type:String, listener:Dynamic, useCapture:Bool = false, priority:Int = 0, useWeakReference:Bool = false):Void {
		priority = flipPriority(type, priority);
		_dispatcher.addEventListener(type, listener, useCapture, priority, useWeakReference);
	}

	public inline function removeEventListener(type:String, listener:Dynamic, useCapture:Bool = false):Void {
		_dispatcher.removeEventListener(type, listener, useCapture);
	}

	public inline function dispatchEvent(event:Event):Bool {
		return _dispatcher.dispatchEvent(event);
	}

	public inline function hasEventListener(type:String):Bool {
		return _dispatcher.hasEventListener(type);
	}

	public inline function willTrigger(type:String):Bool {
		return _dispatcher.willTrigger(type);
	}

	public inline function setCurrentState(state:String):Void {
		if (this.state == state)
			return;
		this.state = state;
		dispatchEvent(new LifecycleEvent(LifecycleEvent.STATE_CHANGE));
	}

	public inline function addReversedEventTypes(types:Array<String>):Void {
		for (i in 0...types.length) {
			_reversedEventTypes[types[i]] = true;
		}
	}

	function configureTransitions():Void {
		_initialize = new LifecycleTransition(LifecycleEvent.PRE_INITIALIZE,
			this).fromStates([LifecycleState.UNINITIALIZED])
			.toStates(LifecycleState.INITIALIZING, LifecycleState.ACTIVE)
			.withEvents(LifecycleEvent.PRE_INITIALIZE, LifecycleEvent.INITIALIZE, LifecycleEvent.POST_INITIALIZE);

		_suspend = new LifecycleTransition(LifecycleEvent.PRE_SUSPEND,
			this).fromStates([LifecycleState.ACTIVE])
			.toStates(LifecycleState.SUSPENDING, LifecycleState.SUSPENDED)
			.withEvents(LifecycleEvent.PRE_SUSPEND, LifecycleEvent.SUSPEND, LifecycleEvent.POST_SUSPEND)
			.inReverse();

		_resume = new LifecycleTransition(LifecycleEvent.PRE_RESUME,
			this).fromStates([LifecycleState.SUSPENDED])
			.toStates(LifecycleState.RESUMING, LifecycleState.ACTIVE)
			.withEvents(LifecycleEvent.PRE_RESUME, LifecycleEvent.RESUME, LifecycleEvent.POST_RESUME);

		_destroy = new LifecycleTransition(LifecycleEvent.PRE_DESTROY,
			this).fromStates([LifecycleState.SUSPENDED, LifecycleState.ACTIVE])
			.toStates(LifecycleState.DESTROYING, LifecycleState.DESTROYED)
			.withEvents(LifecycleEvent.PRE_DESTROY, LifecycleEvent.DESTROY, LifecycleEvent.POST_DESTROY)
			.inReverse();
	}

	function flipPriority(type:String, priority:Int):Int {
		return (priority == 0 && _reversedEventTypes[type]) ? (_reversePriority++) : priority;
	}

	function createSyncLifecycleListener(handler:Dynamic, once:Bool = false):Dynamic {
		// When and After handlers can not be asynchronous
		var length:Int = Reflect.getProperty(handler, "length");
		if (length > 1) {
			throw new LifecycleError(LifecycleError.SYNC_HANDLER_ARG_MISMATCH);
		}

		// CHECK
		var syncLifecycleListener:SyncLifecycleListener = new SyncLifecycleListener();
		return syncLifecycleListener.init(handler, once, length);

		// A handler that accepts 1 argument is provided with the event type
		/*if (handler.length == 1)
			{
				return function(event:LifecycleEvent):Void {
					//once && IEventDispatcher(event.target).removeEventListener(event.type, arguments.callee);
					if (once) cast(event.target, IEventDispatcher).removeEventListener(event.type, arguments.callee);
					handler(event.type);
				};
			}

			// Or, just call the handler
			return function(event:LifecycleEvent):Void {
				//once && IEventDispatcher(event.target).removeEventListener(event.type, arguments.callee);
				if (once) cast(event.target, IEventDispatcher).removeEventListener(event.type, arguments.callee);
				handler();
		};*/
	}

	function reportError(message:String):Void {
		var error:LifecycleError = new LifecycleError(message);
		if (hasEventListener(LifecycleEvent.ERROR)) {
			var event:LifecycleEvent = new LifecycleEvent(LifecycleEvent.ERROR, error);
			dispatchEvent(event);
		} else {
			throw error;
		}
	}
}

@:keepSub
class SyncLifecycleListener {
	var once:Bool;
	var handler:Dynamic;

	public function new() {}

	public function init(handler:Dynamic, once:Bool, handlerLength:Int) {
		this.handler = handler;
		this.once = once;
		if (handlerLength == 1)
			return createSyncLifecycleListenerFunction;
		return createSyncLifecycleListenerFunction2;
	}

	function createSyncLifecycleListenerFunction(event:LifecycleEvent):Void {
		if (once)
			cast(event.target, IEventDispatcher).removeEventListener(event.type, createSyncLifecycleListenerFunction);
		handler(event.type);
	}

	function createSyncLifecycleListenerFunction2(event:LifecycleEvent):Void {
		if (once)
			cast(event.target, IEventDispatcher).removeEventListener(event.type, createSyncLifecycleListenerFunction2);
		handler();
	}
}
