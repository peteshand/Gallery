package eva;

@:keepSub
class LifecycleState {
	public static var UNINITIALIZED:String = "uninitialized";
	public static var INITIALIZING:String = "initializing";
	public static var ACTIVE:String = "active";
	public static var SUSPENDING:String = "suspending";
	public static var SUSPENDED:String = "suspended";
	public static var RESUMING:String = "resuming";
	public static var DESTROYING:String = "destroying";
	public static var DESTROYED:String = "destroyed";
}
