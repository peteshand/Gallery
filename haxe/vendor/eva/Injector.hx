package eva;

import polyfill.system.ApplicationDomain;
import inject.Injector as BaseInjector;
import eva.IInjector;

@:keepSub
class Injector extends BaseInjector implements IInjector {
	public var parent(get, set):IInjector;

	public function set_parent(parentInjector:IInjector):IInjector {
		this.parentInjector = cast(parentInjector, Injector);
		return cast(parentInjector, IInjector);
	}

	public function get_parent():IInjector {
		return cast(this.parentInjector, Injector);
	}

	public function createChild(applicationDomain:ApplicationDomain = null):IInjector {
		var childInjector:IInjector = new Injector();
		if (applicationDomain != null)
			childInjector.applicationDomain = applicationDomain;
		else
			childInjector.applicationDomain = this.applicationDomain;
		childInjector.parent = this;
		return childInjector;
	}
}
