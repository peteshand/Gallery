package eva.ext.display.webGL;

import eva.ext.display.base.DisplayExtension;
import eva.ext.display.base.api.IRenderContext;
import eva.ext.display.webGL.WebGLRenderContext;
import eva.IContext;
import eva.IExtension;

/**
 * ...
 * @author P.J.Shand
 *
 */
@:keepSub
class WebGLStackExtension implements IExtension {
	public function extend(context:IContext):Void {
		context.install(DisplayExtension);
		context.injector.map(IRenderContext).toSingleton(WebGLRenderContext);
	}
}
