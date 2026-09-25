package eva.ext.eventDispatcher.impl;

import polyfill.events.IEventDispatcher;

@:keepSub
class EventRelay {
	var _source:IEventDispatcher;
	var _destination:IEventDispatcher;
	var _types:Array<Dynamic>;
	var _active:Bool = false;

	public function new(source:IEventDispatcher, destination:IEventDispatcher, types:Array<Dynamic> = null) {
		_source = source;
		_destination = destination;
		if (types != null)
			_types = types;
		else
			_types = [];
	}

	public function start():EventRelay {
		if (!_active) {
			_active = true;
			addListeners();
		}
		return this;
	}

	public function stop():EventRelay {
		if (_active) {
			_active = false;
			removeListeners();
		}
		return this;
	}

	public function addType(eventType:String):Void {
		_types.push(eventType);
		if (_active)
			addListener(eventType);
	}

	public function removeType(eventType:String):Void {
		var index:Int = _types.indexOf(eventType);
		if (index > -1) {
			_types.splice(index, 1);
			removeListener(eventType);
		}
	}

	function removeListener(type:String):Void {
		_source.removeEventListener(type, _destination.dispatchEvent);
	}

	function addListener(type:String):Void {
		_source.addEventListener(type, _destination.dispatchEvent);
	}

	function addListeners():Void {
		for (type in _types) {
			addListener(type);
		}
	}

	function removeListeners():Void {
		for (type in _types) {
			removeListener(type);
		}
	}
}
