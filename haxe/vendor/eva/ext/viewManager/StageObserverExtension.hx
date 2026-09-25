package eva.ext.viewManager;

import eva.ext.viewManager.impl.ContainerRegistry;
import eva.ext.viewManager.impl.StageObserver;
import eva.IContext;
import eva.IExtension;
import eva.IInjector;

@:keepSub
class StageObserverExtension implements IExtension {
	static var _stageObserver:StageObserver;
	static var _installCount:UInt;

	var _injector:IInjector;

	public function extend(context:IContext):Void {
		context.whenInitializing(whenInitializing);
		context.whenDestroying(whenDestroying);
		_installCount++;
		_injector = context.injector;
	}

	function whenInitializing():Void {
		if (_stageObserver == null) {
			var containerRegistry:ContainerRegistry = _injector.getInstance(ContainerRegistry);
			trace("Creating genuine StageObserver Singleton");
			_stageObserver = new StageObserver(containerRegistry);
		}
	}

	function whenDestroying():Void {
		_installCount--;
		if (_installCount == 0) {
			trace("Destroying genuine StageObserver Singleton");
			_stageObserver.destroy();
			_stageObserver = null;
		}
	}
}
