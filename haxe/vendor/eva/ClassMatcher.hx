package eva;

import eva.IMatcher;

@:keepSub
class ClassMatcher implements IMatcher {
	public function new() {}

	public function matches(item:Dynamic):Bool {
		return Std.isOfType(item, Class);
	}
}
