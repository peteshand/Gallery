package eva;

import eva.IInjector;
import eva.Guard;
import eva.Guard.GuardFunction;
import eva.Guard.GuardObject;
import eva.Guard.GuardClass;

@:keepSub
class GuardsApprove {
	public static function call(guards:Array<Guard>, injector:IInjector = null):Bool {
		for (guard in guards) {
			if (Reflect.isFunction(guard)) {
				var guardFunction:GuardFunction = guard;
				if (guardFunction() == false)
					return false;
			} else {
				var guardObject:GuardObject = null;
				if (Std.isOfType(guard, Class)) {
					var _GuardClass:GuardClass = guard;
					if (injector != null) {
						guardObject = injector.instantiateUnmapped(_GuardClass);
					} else {
						guardObject = Type.createInstance(guard, []);
					}
				} else {
					guardObject = guard;
				}
				if (guardObject != null) {
					if (guardObject.approve() == false)
						return false;
				}
			}
		}
		return true;
	}
}
