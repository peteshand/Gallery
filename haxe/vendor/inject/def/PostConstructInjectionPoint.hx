package inject.def;

@:keepSub
class PostConstructInjectionPoint extends OrderedInjectionPoint {
	public function new(methodName:String, parameters:Array<String>, requiredParameters:UInt, order:Int) {
		super(methodName, parameters, requiredParameters, order);
	}
}
