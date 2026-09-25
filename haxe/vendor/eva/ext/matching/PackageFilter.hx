package eva.ext.matching;

@:keepSub
class PackageFilter implements ITypeFilter {
	var _descriptor:String;

	public var descriptor(get, null):String;
	public var allOfTypes(get, null):Array<Class<Dynamic>>;
	public var anyOfTypes(get, null):Array<Class<Dynamic>>;
	public var noneOfTypes(get, null):Array<Class<Dynamic>>;

	function get_descriptor():String {
		if (_descriptor == null)
			_descriptor = createDescriptor();
		return _descriptor;
	}

	function get_allOfTypes():Array<Class<Dynamic>> {
		return emptyVector;
	}

	function get_anyOfTypes():Array<Class<Dynamic>> {
		return emptyVector;
	}

	function get_noneOfTypes():Array<Class<Dynamic>> {
		return emptyVector;
	}

	var emptyVector:Array<Class<Dynamic>> = new Array<Class<Dynamic>>();
	var _requirePackage:String;
	var _anyOfPackages:Array<String>;
	var _noneOfPackages:Array<String>;

	public function new(requiredPackage:String, anyOfPackages:Array<String>, noneOfPackages:Array<String>) {
		_requirePackage = requiredPackage;
		_anyOfPackages = anyOfPackages;
		_noneOfPackages = noneOfPackages;
		_anyOfPackages.sort(stringSort);
		_noneOfPackages.sort(stringSort);
	}

	public function matches(item:Dynamic):Bool {
		var fqcn:String = Type.getClassName(item);
		var packageName:String;

		if (_requirePackage != null && (!matchPackageInFQCN(_requirePackage, fqcn)))
			return false;

		for (packageName in _noneOfPackages) {
			if (matchPackageInFQCN(packageName, fqcn))
				return false;
		}

		for (packageName in _anyOfPackages) {
			if (matchPackageInFQCN(packageName, fqcn))
				return true;
		}
		if (_anyOfPackages.length > 0)
			return false;

		if (_requirePackage != null)
			return true;

		if (_noneOfPackages.length > 0)
			return true;

		return false;
	}

	function stringSort(item1:String, item2:String):Int {
		if (item1 > item2) {
			return 1;
		}
		return -1;
	}

	function createDescriptor():String {
		return "require: " + _requirePackage + ", any of: " + _anyOfPackages.toString() + ", none of: " + _noneOfPackages.toString();
	}

	function matchPackageInFQCN(packageName:String, fqcn:String):Bool {
		return (fqcn.indexOf(packageName) == 0);
	}
}
