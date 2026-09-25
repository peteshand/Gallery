package eva;

import eva.IBundle;
import eva.IContext;
import eva.IExtension;
import eva.IExtension.IExtension_Or_Class;
import haxe.ds.ObjectMap;

@:keepSub
class ExtensionInstaller {
	var _classes = new ObjectMap<Dynamic, Bool>();
	var _context:IContext;

	public function new(context:IContext) {
		_context = context;
	}

	public function install(extension:IExtension_Or_Class):Void {
		if (extension == null)
			return;
		if (Std.isOfType(extension, Class))
			installClass(extension);
		else {
			var iextension:IExtension = extension;
			installInstance(iextension);
		}
	}

	inline function installClass(extension:Class<IExtension>) {
		if (_classes.get(extension) == true)
			return;

		var extensionInstance = Type.createInstance(extension, []);
		installInstance(extensionInstance);
	}

	inline function installInstance(extension:IExtension) {
		var extensionClass:Class<IExtension> = Type.getClass(extension);
		if (_classes.get(extensionClass) == true)
			return;
		_classes.set(extensionClass, true);

		// trace("Installing extension {0}", [Type.getClassName(extensionClass)]);

		if (extension.extend != null) {
			extension.extend(_context);
		}
	}

	public function destroy():Void {
		for (_class in _classes.keys()) {
			_classes.remove(_class);
		}
	}
}
