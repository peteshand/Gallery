package eva.ext.display.base;

import eva.ext.display.base.api.ILayers;
import eva.ext.display.base.api.IRenderer;
import eva.ext.display.base.api.IStack;
import eva.ext.display.base.api.IViewport;
import eva.ext.display.base.impl.Layers;
import eva.ext.display.base.impl.Renderer;
import eva.ext.display.base.impl.Stack;
import eva.ext.display.base.impl.Viewport;
import eva.IContext;
import eva.IExtension;

/**
 * ...
 * @author P.J.Shand
 */
@:keepSub
class DisplayExtension implements IExtension {
	public function new() {}

	public function extend(context:IContext):Void {
		context.injector.map(ILayers).toSingleton(Layers);
		context.injector.map(IStack).toSingleton(Stack);
		context.injector.map(IRenderer).toSingleton(Renderer);
		// context.injector.map(IRenderContext).toSingleton(Stage3DRenderContext);
		context.injector.map(IViewport).toSingleton(Viewport);

		var layers:ILayers = context.injector.getInstance(ILayers);
		layers.init();
	}
}
