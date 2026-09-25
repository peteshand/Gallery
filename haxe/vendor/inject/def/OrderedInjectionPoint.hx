package inject.def;

@:keepSub
class OrderedInjectionPoint extends MethodInjectionPoint {
	public var order:Int;

	public function new(methodName:String, parameters:Array<String>, requiredParameters:UInt, order:Int) {
		super(methodName, parameters, requiredParameters, false, null);
		this.order = order;
	}
}
