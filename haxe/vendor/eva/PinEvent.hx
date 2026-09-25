package eva;

import polyfill.events.Event;

@:keepSub
class PinEvent extends Event {
	public static var DETAIN:String = "detain";
	public static var RELEASE:String = "release";

	var _instance:Dynamic;

	public var instance(default, null):Dynamic;

	public function new(type:String, instance:Dynamic) {
		super(type);
		_instance = instance;
	}

	override public function clone():Event {
		return new PinEvent(type, _instance);
	}
}
