package inject.def;

@:keepSub
class PreDestroyInjectionPoint extends OrderedInjectionPoint {
	public function new(methodName:String, parameters:Array<String>, requiredParameters:UInt, order:Int) {
		super(methodName, parameters, requiredParameters, order);
	}
}
