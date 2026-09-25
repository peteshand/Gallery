package signals;

import signals.Signal.BaseSignal;
import signals.Signal.SignalCallbackData;

@:expose("Signal3")
class Signal3<T, K, I> extends BaseSignal<(T, K, I) -> Void> {
	public var value1:T;
	public var value2:K;
	public var value3:I;

	override public function new() {
		super();
		this.defaultCallbackProps = 3;
	}

	public function dispatch(value1:T, value2:K, value3:I) {
		sortPriority();
		this.value1 = value1;
		this.value2 = value2;
		this.value3 = value3;
		dispatchCallbacks();
		value1 = null;
		value2 = null;
		value3 = null;
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

	override function dispatchCallback3(callback:(T, K, I) -> Void, callbackData:SignalCallbackData) {
		callback(value1, value2, value3);
	}
}
