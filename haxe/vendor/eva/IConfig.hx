package eva;

import haxe.extern.EitherType;

@:keepSub
interface IConfig {
	function configure():Void;
}

typedef IConfig_Or_Class = EitherType<IConfig, Class<IConfig>>;
