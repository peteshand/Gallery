package eva.ext.location;

import eva.IContext;
import eva.IBundle;

/**
 * ...
 * @author P.J.Shand
 */
class LocationBundle implements IBundle {
	public function extend(context:IContext):Void {
		context.install(LocationExtension);
	}
}
