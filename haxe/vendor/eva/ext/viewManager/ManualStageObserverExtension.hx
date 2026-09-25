package eva.ext.viewManager;

import eva.ext.viewManager.impl.ContainerRegistry;
import eva.ext.viewManager.impl.ManualStageObserver;
import eva.IContext;
import eva.IExtension;
import eva.IInjector;

@:keepSub
class ManualStageObserverExtension implements IExtension {
	static var _manualStageObserver:ManualStageObserver;
	static var _installCount:UInt;

	var _injector:IInjector;

	public function extend(context:IContext):Void {
		context.whenInitializing(whenInitializing);
		context.whenDestroying(whenDestroying);
		_installCount++;
		_injector = context.injector;
	}

	function whenInitializing():Void {
		if (_manualStageObserver == null) {
			var containerRegistry:ContainerRegistry = _injector.getInstance(ContainerRegistry);
			trace("Creating genuine ManualStageObserver Singleton");
			_manualStageObserver = new ManualStageObserver(containerRegistry);
		}
	}

	function whenDestroying():Void {
		_installCount--;
		if (_installCount == 0) {
			trace("Destroying genuine ManualStageObserver Singleton");
			_manualStageObserver.destroy();
			_manualStageObserver = null;
		}
	}
}
