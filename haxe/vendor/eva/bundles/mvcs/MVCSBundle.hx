package eva.bundles.mvcs;

import eva.ext.contextView.ContextViewExtension;
import eva.ext.contextView.StageSyncExtension;
import eva.ext.contextView.ContextViewListenerConfig;
import eva.ext.mediatorMap.MediatorMapExtension;
import eva.ext.modularity.ModularityExtension;
import eva.ext.viewManager.StageCrawlerExtension;
import eva.ext.viewManager.StageObserverExtension;
import eva.ext.viewManager.ViewManagerExtension;
import eva.ext.viewProcessorMap.ViewProcessorMapExtension;
import eva.IBundle;
import eva.IContext;

@:keepSub
class MVCSBundle extends MCSBundle implements IBundle {
	override public function extend(context:IContext):Void {
		super.extend(context);

		context.install(ContextViewExtension);
		context.install(StageSyncExtension);
		context.install(ModularityExtension);
		context.install(MediatorMapExtension);
		context.install(ViewManagerExtension);
		context.install(StageObserverExtension);
		context.install(ViewProcessorMapExtension);
		context.install(StageCrawlerExtension);
		context.configure(ContextViewListenerConfig);
	}
}
