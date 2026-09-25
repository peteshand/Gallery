package eva;

import polyfill.events.IEventDispatcher;
import eva.PinEvent;

@:keepSub
class Pin {
	var _instances = new Map<String, Dynamic>();
	var _dispatcher:IEventDispatcher;

	public function new(dispatcher:IEventDispatcher) {
		_dispatcher = dispatcher;
	}

	public function detain(instance:Dynamic):Void {
		if (_instances[instance] == null) {
			_instances[instance] = true;
			_dispatcher.dispatchEvent(new PinEvent(PinEvent.DETAIN, instance));
		}
	}

	public function release(instance:Dynamic):Void {
		if (_instances[instance]) {
			_instances.remove(instance);
			_dispatcher.dispatchEvent(new PinEvent(PinEvent.RELEASE, instance));
		}
	}

	public function releaseAll():Void {
		for (instance in _instances) {
			release(instance);
		}
	}
}
