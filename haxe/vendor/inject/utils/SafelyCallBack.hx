package inject.utils;

@:keepSub
class SafelyCallBack {
	public static function call(callback:Dynamic, errorMsg:Dynamic = null, message:Dynamic = null) {
		#if (js || cpp)
		callback(errorMsg, message);
		#else
		if (message != null) {
			try {
				callback(errorMsg, message);
			} catch (error:Dynamic) {
				try {
					callback(errorMsg);
				} catch (error2:Dynamic) {
					try {
						callback();
					} catch (error3:Dynamic) {
						trace("Error calling CallBack : " + error3);
					}
				}
			}
		} else if (errorMsg != null) {
			try {
				callback(errorMsg);
			} catch (error2:Dynamic) {
				try {
					callback();
				} catch (error3:Dynamic) {
					trace("Error calling CallBack : " + error3);
				}
			}
		}

		try {
			callback(errorMsg, message);
		} catch (error:Dynamic) {
			try {
				callback(errorMsg);
			} catch (error2:Dynamic) {
				try {
					callback();
				} catch (error3:Dynamic) {
					trace("Error calling CallBack : " + error3);
				}
			}
		}
		#end
	}
}
