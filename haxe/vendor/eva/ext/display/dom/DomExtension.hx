package eva.ext.display.dom;

import eva.IContext;
import eva.IExtension;
import eva.ext.display.dom.api.IDomViewMap;
import eva.ext.display.dom.impl.DomViewMap;

/**
 * ...
 * @author P.J.Shand
 */
@:keepSub
class DomExtension implements IExtension {
	public function new() {}

	public function extend(context:IContext):Void {
		context.injector.map(IDomViewMap).toSingleton(DomViewMap);
		var domViewMap:IDomViewMap = context.injector.getInstance(IDomViewMap);
		domViewMap.initialize();
	}
}
