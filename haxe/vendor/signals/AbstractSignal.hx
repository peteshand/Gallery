package signals;

abstract AbstractSignal(Int) {
    public var numListeners(get, never):Int;

    static var COUNT:Int = 0;
	static var callbacks = new Map<Int, Array<SignalCallbackData2>>();
	static var requiresSort = new Map<Int, Bool>();
	static var priorityUsed = new Map<Int, Bool>();

    inline public function new() {
        this = COUNT++;
        callbacks.set(this, []);
        requiresSort.set(this, false);
        priorityUsed.set(this, false);
    }

    public function dispatch()
	{
		sortPriority();
		dispatchCallbacks();
	}

    inline function sortPriority()
	{
		if (requiresSort.get(this)){
			callbacks.get(this).sort(sortCallbacks);
			requiresSort.set(this, false);
		}
	}

	inline function dispatchCallbacks()
	{
        var _callbacks = callbacks.get(this);
		var i:Int = 0;
		while (i < _callbacks.length) {
			var callbackData = _callbacks[i];
			callbackData.callCount += 1;
			dispatchCallback(callbackData.callback);
			if (callbackData.fireOnce == true){
				_callbacks.splice(i, 1);
			} else {
				i++;
			}
		}
	}

	function dispatchCallback(callback:Dynamic)
	{
		// implement in override
	}

	function sortCallbacks(s1:SignalCallbackData2, s2:SignalCallbackData2):Int
	{
		if (s1.priority > s2.priority) return -1;
		else if (s1.priority < s2.priority) return 1;
		else return 0;
	}

	function get_numListeners()
	{
		return callbacks.get(this).length;
	}

	public function add(callback:Dynamic, ?fireOnce:Bool=false, ?priority:Int = 0):Void
	{
        var _callbacks = callbacks.get(this);
		//_callbacks.push(new 2(callback, 0, fireOnce, priority));
		if (priority != 0) priorityUsed.set(this, true);
		if (priorityUsed.get(this) == true) requiresSort.set(this, true);
	}

	public function remove(callback:Dynamic=null):Void
	{
		if (callback == null){
			callbacks.set(this, []);
		} else {
            var _callbacks = callbacks.get(this);
			var i:Int = 0;
			while (i < _callbacks.length) {
				if (_callbacks[i].callback == callback){
					_callbacks.splice(i, 1);
				} else {
					i++;
				}
			}
		}
	}
}

/*typedef SignalCallbackData2 =
{
	callback:Dynamic,
	callCount:Int,
	fireOnce:Bool,
	priority:Int
}*/

abstract SignalCallbackData2(Array<Dynamic>)
{
    public var callback(get, never):Dynamic;
    public var callCount(get, set):Int;
    public var fireOnce(get, never):Dynamic;
    public var priority(get, never):Int;

    inline public function new(callback:Dynamic, callCount:Int, fireOnce:Bool, priority:Int) {
        this = [callback, callCount, fireOnce, priority];
    }

    function get_callback():Dynamic
	{
		return this[0];
	}

    function get_callCount():Int
	{
		return this[1];
	}

    function set_callCount(value:Int):Int
	{
		this[1] = value;
        return value;
	}

    function get_fireOnce():Bool
	{
		return this[2];
	}

    function get_priority():Int
	{
		return this[3];
	}
}