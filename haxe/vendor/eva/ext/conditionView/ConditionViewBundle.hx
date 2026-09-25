package eva.ext.conditionView;

import eva.IContext;
import eva.IBundle;

/**
 * ...
 * @author P.J.Shand
 */
class ConditionViewBundle implements IBundle {
	public function extend(context:IContext):Void {
		context.install(ConditionViewExtension);
	}
}
