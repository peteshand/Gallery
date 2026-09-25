package eva;

import haxe.extern.EitherType;

@:keepSub
interface IExtension {
	function extend(context:IContext):Void;
}

typedef IExtension_Or_Class = EitherType<IExtension, Class<IExtension>>;
