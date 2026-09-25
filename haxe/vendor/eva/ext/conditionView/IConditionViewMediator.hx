package eva.ext.conditionView;

import condition.IConditionView;
import eva.bundles.mvcs.Mediator;
import delay.Delay;

/**
* ...
* @author P.J.Shand
*/
class IConditionViewMediator extends Mediator
{
    @inject public var view:IConditionView;
    var active:Bool;

    override public function initialize():Void
	{
        active = true;
        Delay.nextFrame(() -> {
            if (active) view.transition.condition = view.condition;
        });
	}
    override public function destroy():Void {
        active = false;
        view.transition.condition = null;
        super.destroy();
    }
}
