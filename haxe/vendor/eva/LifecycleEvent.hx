package eva;

import eva.errors.Error;
import polyfill.events.Event;

@:keepSub
class LifecycleEvent extends Event {
	public static var ERROR:String = "_error";
	public static var STATE_CHANGE:String = "stateChange";
	public static var PRE_INITIALIZE:String = "preInitialize";
	public static var INITIALIZE:String = "initialize";
	public static var POST_INITIALIZE:String = "postInitialize";
	public static var PRE_SUSPEND:String = "preSuspend";
	public static var SUSPEND:String = "suspend";
	public static var POST_SUSPEND:String = "postSuspend";
	public static var PRE_RESUME:String = "preResume";
	public static var RESUME:String = "resume";
	public static var POST_RESUME:String = "postResume";
	public static var PRE_DESTROY:String = "preDestroy";
	public static var DESTROY:String = "destroy";
	public static var POST_DESTROY:String = "postDestroy";

	var _error:Error;

	public var error(default, null):Error;

	public function new(type:String, error:Error = null) {
		super(type);
		_error = error;
	}

	override public function clone():Event {
		return new LifecycleEvent(type, error);
	}
}
