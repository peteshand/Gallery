package eva.bundles.mvcs;

import eva.ext.eventDispatcher.EventDispatcherExtension;
import eva.ext.directCommandMap.DirectCommandMapExtension;
import eva.ext.eventCommandMap.EventCommandMapExtension;
import eva.ext.localEventMap.LocalEventMapExtension;
import eva.ext.logicMap.LogicMapExtension;
import eva.ext.modelMap.ModelExtension;
import eva.ext.config.ConfigExtension;
import eva.IBundle;
import eva.IContext;

@:keepSub
class MCSBundle implements IBundle {
	public function new() {}

	public function extend(context:IContext):Void {
		context.install(EventDispatcherExtension);
		context.install(DirectCommandMapExtension);
		context.install(EventCommandMapExtension);
		context.install(LocalEventMapExtension);
		context.install(LogicMapExtension);
		context.install(ModelExtension);
		context.install(ConfigExtension);
	}
}
