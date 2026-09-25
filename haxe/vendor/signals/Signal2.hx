package signals;

import signals.Signal.BaseSignal;
import signals.Signal.SignalCallbackData;

@:expose("Signal2")
class Signal2<T, K> extends BaseSignal<(T, K) -> Void> {
	public var value1:T;
	public var value2:K;

	override public function new() {
		super();
		this.defaultCallbackProps = 2;
	}

	public function dispatch(value1:T, value2:K) {
		sortPriority();
		this.value1 = value1;
		this.value2 = value2;
		dispatchCallbacks();
		value1 = null;
		value2 = null;
	}

	override function dispatchCallback(callback:() -> Void, callbackData:SignalCallbackData) {
		callback();
	}

	override function dispatchCallback1(callback:(T) -> Void, callbackData:SignalCallbackData) {
		callback(value1);
	}

	override function dispatchCallback2(callback:(T, K) -> Void, callbackData:SignalCallbackData) {
		callback(value1, value2);
	}

	override function dispatchCallback3(callback:(Dynamic, Dynamic, Dynamic) -> Void, callbackData:SignalCallbackData) {
		throw "Use Signal 3";
	}
}
