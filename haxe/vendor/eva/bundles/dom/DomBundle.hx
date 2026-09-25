package eva.bundles.dom;

import eva.ext.mediatorMap.MediatorMapExtension;
import eva.ext.localEventMap.LocalEventMapExtension;
import eva.ext.logicMap.LogicMapExtension;
import eva.ext.display.dom.DomExtension;
import eva.ext.eventDispatcher.EventDispatcherExtension;
import eva.IBundle;
import eva.IContext;

@:keepSub
class DomBundle implements IBundle {
	public function new() {}

	public function extend(context:IContext):Void {
		context.install(LocalEventMapExtension);
		context.install(LogicMapExtension);
		context.install(MediatorMapExtension);
		context.install(EventDispatcherExtension);
		context.install(DomExtension);
	}
}
