package eva.bundles.node;

import eva.ext.directCommandMap.DirectCommandMapExtension;
import eva.ext.eventCommandMap.EventCommandMapExtension;
import eva.ext.eventDispatcher.EventDispatcherExtension;
import eva.ext.localEventMap.LocalEventMapExtension;
import eva.ext.logicMap.LogicMapExtension;
import eva.IBundle;
import eva.IContext;

@:keepSub
class NodeBundle implements IBundle {
	public function new() {}

	public function extend(context:IContext):Void {
		context.install(EventDispatcherExtension, DirectCommandMapExtension, EventCommandMapExtension, LocalEventMapExtension, LogicMapExtension);
	}
}
