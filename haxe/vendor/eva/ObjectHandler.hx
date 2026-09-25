package eva;

import eva.IMatcher;

@:keepSub
class ObjectHandler {
	var _matcher:IMatcher;
	var _handler:Dynamic;

	public function new(matcher:IMatcher, handler:Dynamic) {
		_matcher = matcher;
		_handler = handler;
	}

	public function handle(object:Dynamic):Void {
		if (_matcher.matches(object)) {
			_handler(object);
		}
	}
}
