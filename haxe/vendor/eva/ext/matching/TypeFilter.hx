package eva.ext.matching;

@:keepSub
class TypeFilter implements ITypeFilter {
	public var allOfTypes(get, null):Array<Class<Dynamic>>;
	public var anyOfTypes(get, null):Array<Class<Dynamic>>;
	public var noneOfTypes(get, null):Array<Class<Dynamic>>;
	public var descriptor(get, null):String;

	function get_allOfTypes():Array<Class<Dynamic>> {
		return this.allOfTypes;
	}

	function get_anyOfTypes():Array<Class<Dynamic>> {
		return this.anyOfTypes;
	}

	function get_noneOfTypes():Array<Class<Dynamic>> {
		return this.noneOfTypes;
	}

	function get_descriptor():String {
		if (this.descriptor == null)
			this.descriptor = createDescriptor();
		return this.descriptor;
	}

	public function new(allOf:Array<Class<Dynamic>>, anyOf:Array<Class<Dynamic>>, noneOf:Array<Class<Dynamic>>) {
		if (allOf == null || anyOf == null || noneOf == null)
			throw 'TypeFilter parameters can not be null';
		this.allOfTypes = allOf;
		this.anyOfTypes = anyOf;
		this.noneOfTypes = noneOf;
	}

	public function matches(item:Dynamic):Bool {
		var i:UInt = this.allOfTypes.length;
		while (i-- > 0) {
			if (!(Std.isOfType(item, this.allOfTypes[i]))) {
				return false;
			}
		}

		i = this.noneOfTypes.length;
		while (i-- > 0) {
			if (Std.isOfType(item, this.noneOfTypes[i])) {
				return false;
			}
		}

		if (this.anyOfTypes.length == 0 && (this.allOfTypes.length > 0 || this.noneOfTypes.length > 0)) {
			return true;
		}

		i = this.anyOfTypes.length;
		while (i-- > 0) {
			if (Std.isOfType(item, this.anyOfTypes[i])) {
				return true;
			}
		}

		return false;
	}

	function alphabetiseCaseInsensitiveFCQNs(classVector:Array<Class<Dynamic>>):Array<String> {
		var fqcn:String;
		var allFCQNs = new Array<String>();

		var iLength:UInt = classVector.length;
		for (i in 0...iLength) {
			fqcn = Type.getClassName(classVector[i]);
			allFCQNs[allFCQNs.length] = fqcn;
		}

		allFCQNs.sort(stringSort);
		return allFCQNs;
	}

	function createDescriptor():String {
		var allOf_FCQNs = alphabetiseCaseInsensitiveFCQNs(allOfTypes);
		var anyOf_FCQNs = alphabetiseCaseInsensitiveFCQNs(anyOfTypes);
		var noneOf_FQCNs = alphabetiseCaseInsensitiveFCQNs(noneOfTypes);
		return "all of: " + allOf_FCQNs.toString() + ", any of: " + anyOf_FCQNs.toString() + ", none of: " + noneOf_FQCNs.toString();
	}

	function stringSort(item1:String, item2:String):Int {
		if (item1 < item2) {
			return 1;
		}
		return -1;
	}
}
