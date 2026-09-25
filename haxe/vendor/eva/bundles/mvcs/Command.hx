package eva.bundles.mvcs;

import inject.utils.DescribedType;
import eva.ext.commandCenter.api.ICommand;

@:keepSub
class Command implements DescribedType implements ICommand {
	public function execute():Void {}
}
