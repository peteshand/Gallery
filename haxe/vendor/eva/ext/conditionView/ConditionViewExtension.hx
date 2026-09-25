package eva.ext.conditionView;

import condition.IConditionView;
import inject.utils.DescribedType;
import eva.ext.conditionView.IConditionViewMediator;
import eva.ext.mediatorMap.api.IMediatorMap;
import eva.IContext;
import eva.IExtension;

class ConditionViewExtension implements DescribedType implements IExtension
{
	public function new() { }
	
	public function extend(context:IContext):Void
	{
		var mediatorMap:IMediatorMap = context.injector.getInstance(IMediatorMap);
		mediatorMap.map(IConditionView).toMediator(IConditionViewMediator);
	}
}