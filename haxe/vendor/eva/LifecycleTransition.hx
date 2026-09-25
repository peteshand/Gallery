package eva;

import eva.LifecycleEvent;
import inject.utils.SafelyCallBack;

@:keepSub
class LifecycleTransition {
	var _fromStates:Array<String> = [];
	var _dispatcher:MessageDispatcher = new MessageDispatcher();
	var _callbacks:Array<Dynamic> = [];
	var _name:String;
	var _lifecycle:Lifecycle;
	var _transitionState:String;
	var _finalState:String;
	var _preTransitionEvent:String;
	var _transitionEvent:String;
	var _postTransitionEvent:String;
	var _reverse:Bool = false;

	public function new(name:String, lifecycle:Lifecycle) {
		_name = name;
		_lifecycle = lifecycle;
	}

	public function fromStates(states:Array<String>):LifecycleTransition {
		for (state in states) {
			_fromStates.push(state);
		}
		return this;
	}

	public function toStates(transitionState:String, finalState:String):LifecycleTransition {
		_transitionState = transitionState;
		_finalState = finalState;
		return this;
	}

	public function withEvents(preTransitionEvent:String, transitionEvent:String, postTransitionEvent:String):LifecycleTransition {
		_preTransitionEvent = preTransitionEvent;
		_transitionEvent = transitionEvent;
		_postTransitionEvent = postTransitionEvent;

		if (_reverse) {
			_lifecycle.addReversedEventTypes([preTransitionEvent, transitionEvent, postTransitionEvent]);
		}

		return this;
	}

	public function inReverse():LifecycleTransition {
		_reverse = true;
		_lifecycle.addReversedEventTypes([_preTransitionEvent, _transitionEvent, _postTransitionEvent]);
		return this;
	}

	public function addBeforeHandler(handler:Void->Void):LifecycleTransition {
		_dispatcher.addMessageHandler(_name, handler);
		return this;
	}

	public function enter(callback:Dynamic = null):Void {
		if (_lifecycle.state == _finalState) {
			if (callback != null)
				SafelyCallBack.call(callback, null, _name);
			return;
		}

		if (_lifecycle.state == _transitionState) {
			if (callback != null)
				_callbacks.push(callback);
			return;
		}

		if (invalidTransition()) {
			if (callback != null)
				reportError("Invalid transition", [callback]);
			return;
		}

		var initialState:String = _lifecycle.state;

		if (callback != null)
			_callbacks.push(callback);

		setState(_transitionState);

		_dispatcher.dispatchMessage(_name, function(error:Dynamic):Void {
			if (error) {
				setState(initialState);
				reportError(error, _callbacks);
				return;
			}

			dispatch(_preTransitionEvent);
			dispatch(_transitionEvent);

			setState(_finalState);

			var callbacks:Array<Dynamic> = _callbacks.concat([]);
			_callbacks = [];
			for (callback in callbacks)
				SafelyCallBack.call(callback, null, _name);

			dispatch(_postTransitionEvent);
		}, _reverse);
	}

	function invalidTransition():Bool {
		return _fromStates.length > 0 && _fromStates.indexOf(_lifecycle.state) == -1;
	}

	function setState(state:String):Void {
		if (state != null && state != "")
			_lifecycle.setCurrentState(state);
	}

	function dispatch(type:String):Void {
		if (type != null && type != "" && _lifecycle.hasEventListener(type)) {
			_lifecycle.dispatchEvent(new LifecycleEvent(type));
		}
	}

	function reportError(message:Dynamic, callbacks:Array<Dynamic> = null):Void {
		var error = message;

		if (_lifecycle.hasEventListener(LifecycleEvent.ERROR)) {
			var event:LifecycleEvent = new LifecycleEvent(LifecycleEvent.ERROR, error);
			_lifecycle.dispatchEvent(event);
			if (callbacks != null) {
				for (callback in callbacks)
					if (callback != null)
						SafelyCallBack.call(callback, error, _name);
				callbacks = [];
			}
		} else {
			throw error;
		}
	}
}
