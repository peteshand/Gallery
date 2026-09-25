package eva;

import eva.IInjector;

@:keepSub
class ApplyHooks {
	public static function call(hooks:Array<Dynamic>, injector:IInjector = null):Void {
		for (hook in hooks) {
			if (Reflect.isFunction(hook)) {
				hook();
				continue;
			}

			if (Std.isOfType(hook, Class)) {
				hook = (injector != null) ? injector.instantiateUnmapped(cast(hook,
					Class<Dynamic>)) /*: Type.createInstance(hook, []);*/ : Type.createInstance(hook, []);
			}
			hook.hook();
		}
	}
}
