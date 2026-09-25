package eva;

import eva.errors.Error;

@:keepSub
class LifecycleError extends Error {
	public static var SYNC_HANDLER_ARG_MISMATCH:String = "When and After handlers must accept 0 or 1 arguments";
	public static var LATE_HANDLER_ERROR_MESSAGE:String = "Handler added late and will never fire";

	public function new(message:String) {
		super(message);
	}
}
