package eva.ext.eventDispatcher.impl;

import polyfill.events.IEventDispatcher;
import eva.LifecycleEvent;

@:keepSub
class LifecycleEventRelay {
	static var TYPES:Array<Dynamic> = [
		LifecycleEvent.STATE_CHANGE, LifecycleEvent.PRE_INITIALIZE, LifecycleEvent.INITIALIZE, LifecycleEvent.POST_INITIALIZE, LifecycleEvent.PRE_SUSPEND,
		LifecycleEvent.SUSPEND, LifecycleEvent.POST_SUSPEND, LifecycleEvent.PRE_RESUME, LifecycleEvent.RESUME, LifecycleEvent.POST_RESUME,
		LifecycleEvent.PRE_DESTROY, LifecycleEvent.DESTROY, LifecycleEvent.POST_DESTROY
	];

	var _relay:EventRelay;

	public function new(source:IEventDispatcher, destination:IEventDispatcher) {
		_relay = new EventRelay(source, destination, TYPES).start();
	}

	public function destroy():Void {
		_relay.stop();
		_relay = null;
	}
}
