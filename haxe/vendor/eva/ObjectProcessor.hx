package eva;

import eva.IMatcher;

@:keepSub
class ObjectProcessor {
	var _handlers:Array<Dynamic> = [];

	public function new() {}

	public function addObjectHandler(matcher:IMatcher, handler:Dynamic):Void {
		_handlers.push(new ObjectHandler(matcher, handler));
	}

	public function processObject(object:Dynamic):Void {
		for (handler in _handlers) {
			handler.handle(object);
		}
	}

	public function removeAllHandlers():Void {
		_handlers = [];
	}
}
