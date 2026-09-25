package eva;

import inject.utils.UID;
import eva.IConfig;
import eva.IContext;
import eva.IInjector;
import eva.IMatcher;
import eva.LifecycleEvent;
import eva.IConfig.IConfig_Or_Class;

@:keepSub
class ConfigManager {
	var _objectProcessor:ObjectProcessor = new ObjectProcessor();
	var _configs = new Map<String, Bool>();
	var _queue:Array<Dynamic> = [];
	var _injector:IInjector;
	var _initialized:Bool = false;
	var _context:IContext;

	public function new(context:IContext) {
		_context = context;

		_injector = context.injector;
		addConfigHandler(new ClassMatcher(), handleClass);
		addConfigHandler(new ObjectMatcher(), handleObject);
		context.addEventListener(LifecycleEvent.INITIALIZE, initialize, false, -100);
	}

	public function addConfig(config:IConfig_Or_Class):Void {
		if (config == null)
			return;

		#if (js)
		if (!Std.isOfType(config, Class)) {
			Reflect.setProperty(config, "constructor", Type.getClass(config));
		}
		#end

		var id = UID.instanceID(config);
		if (_configs[id] == null) {
			_configs[id] = true;
			_objectProcessor.processObject(config);
		}
	}

	public function addConfigHandler(matcher:IMatcher, handler:Dynamic):Void {
		_objectProcessor.addObjectHandler(matcher, handler);
	}

	public function destroy():Void {
		_context.removeEventListener(LifecycleEvent.INITIALIZE, initialize);
		_objectProcessor.removeAllHandlers();
		_queue = [];
		for (config in _configs) {
			_configs.remove(UID.clearInstanceID(config));
		}
	}

	function initialize(event:LifecycleEvent):Void {
		if (_initialized == false) {
			_initialized = true;
			processQueue();
		}
	}

	function handleClass(type:Class<Dynamic>):Void {
		if (_initialized) {
			// trace("Already initialized. Instantiating config class {0}", [type]);
			processClass(type);
		} else {
			// trace("Not yet initialized. Queuing config class {0}", [type]);
			_queue.push(type);
		}
	}

	function handleObject(object:Dynamic):Void {
		if (_initialized) {
			// trace("Already initialized. Injecting into config object {0}", [object]);
			processObject(object);
		} else {
			// trace("Not yet initialized. Queuing config object {0}", [object]);
			_queue.push(object);
		}
	}

	function processQueue():Void {
		for (config in _queue) {
			if (Std.isOfType(config, Class)) {
				/*#if js
					trace("Now initializing. Instantiating config class {0}", [Type.getClassName(config)]);
					#else
					trace("Now initializing. Instantiating config class {0}", [config]);
					#end */

				processClass(cast(config, Class<Dynamic>));
			} else {
				/*#if js
					trace("Now initializing. Injecting into config object {0}", [Type.getClassName((Type.getClass(config)))]);
					#else
					trace("Now initializing. Injecting into config object {0}", [config]);
					#end */

				processObject(config);
			}
		}
		_queue = [];
	}

	function processClass(type:Class<Dynamic>):Void {
		processObject(_injector.getOrCreateNewInstance(type), false);
	}

	function processObject(object:IConfig, inject:Bool = true):Void {
		if (object == null)
			return;
		if (inject)
			_injector.injectInto(object);

		var configure:Void->Void = object.configure;
		if (configure != null)
			configure();
	}
}
