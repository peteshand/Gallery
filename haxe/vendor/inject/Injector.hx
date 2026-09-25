package inject;

#if openfl
import openfl.system.ApplicationDomain;
import openfl.events.EventDispatcher;
#else
import polyfill.system.ApplicationDomain;
import polyfill.events.EventDispatcher;
#end
import inject.reflection.RuntimeTypeReflector;
import inject.reflection.MacroTypeReflector;
import inject.utils.UID;
import inject.provider.DependencyProvider;
import inject.provider.FallbackDependencyProvider;
import inject.provider.LocalOnlyProvider;
import inject.provider.SoftDependencyProvider;
import inject.mapping.InjectionMapping;
import inject.mapping.MappingEvent;
import inject.reflection.Reflector;
import inject.def.ConstructorInjectionPoint;
import inject.def.InjectionPoint;
import inject.def.PreDestroyInjectionPoint;
import inject.def.TypeDescription;
import inject.utils.TypeDescriptor;

@:keepSub
class Injector extends EventDispatcher {
	static var INJECTION_POINTS_CACHE = new Map<String, TypeDescription>();

	@:isVar public var parentInjector(get, set):Injector;

	@:isVar public var applicationDomain(get, set):ApplicationDomain;
	@:isVar public var fallbackProvider(get, set):FallbackDependencyProvider;
	@:isVar public var blockParentFallbackProvider(get, set):Bool = false;

	private var _classDescriptor:TypeDescriptor;
	private var _mappings:Map<String, InjectionMapping>;

	private var _mappingsInProcess:Map<String, Bool>;
	private var _managedObjects:Map<String, Dynamic>;
	private var _reflector:Reflector;

	#if js
	private static var _baseTypes:Array<String> = initBaseTypeMappingIds([Array, Class]);
	#else
	private static var _baseTypes:Array<String> = initBaseTypeMappingIds([Dynamic, Array, Class, Float, Int, String]);
	#end

	private static function initBaseTypeMappingIds(types:Array<Dynamic>):Array<String> {
		var returnArray = new Array<String>();
		for (i in 0...types.length) {
			returnArray.push(Type.getClassName(types[i]) + '|');
		}
		return returnArray;
	}

	public var providerMappings = new Map<String, DependencyProvider>();

	public function new() {
		_mappings = new Map<String, InjectionMapping>();
		_mappingsInProcess = new Map<String, Bool>();
		_managedObjects = new Map<String, Dynamic>();
		_reflector = new MacroTypeReflector(new RuntimeTypeReflector());

		_classDescriptor = new TypeDescriptor(_reflector, INJECTION_POINTS_CACHE);
		this.applicationDomain = ApplicationDomain.currentDomain;
		super();
	}

	function get_parentInjector():Injector {
		return this.parentInjector;
	}

	function set_parentInjector(parentInjector:Injector):Injector {
		this.parentInjector = parentInjector;
		return this.parentInjector;
	}

	function get_applicationDomain():ApplicationDomain {
		return this.applicationDomain;
	}

	function set_applicationDomain(applicationDomain:ApplicationDomain):ApplicationDomain {
		if (applicationDomain != null)
			this.applicationDomain = applicationDomain;
		else
			this.applicationDomain = ApplicationDomain.currentDomain;
		return this.applicationDomain;
	}

	function get_fallbackProvider():FallbackDependencyProvider {
		return this.fallbackProvider;
	}

	function set_fallbackProvider(provider:FallbackDependencyProvider):FallbackDependencyProvider {
		this.fallbackProvider = provider;
		return provider;
	}

	function get_blockParentFallbackProvider():Bool {
		return this.blockParentFallbackProvider;
	}

	function set_blockParentFallbackProvider(value:Bool):Bool {
		this.blockParentFallbackProvider = value;
		return value;
	}

	public function map(type:Class<Dynamic>, name:String = ''):InjectionMapping {
		var mappingId:String = Type.getClassName(type) + '|' + name;
		if (_mappings.exists(mappingId))
			return _mappings.get(mappingId);
		return createMapping(type, name, mappingId);
	}

	public function unmap(type:Class<Dynamic>, name:String = ''):Void {
		var mappingId:String = Type.getClassName(type) + '|' + name;
		var mapping:InjectionMapping = _mappings.get(mappingId);
		if (mapping != null && mapping.isSealed) {
			throw 'Can\'t unmap a sealed mapping';
		}
		if (mapping == null) {
			throw 'Error while removing an injector mapping: ' + 'No mapping defined for dependency ' + mappingId;
		}
		mapping.getProvider().destroy();
		_mappings.remove(mappingId);
		providerMappings.remove(mappingId);
		hasEventListener(MappingEvent.POST_MAPPING_REMOVE) && dispatchEvent(new MappingEvent(MappingEvent.POST_MAPPING_REMOVE, type, name, null));

	}
	public function satisfies(type:Class<Dynamic>, name:String = ''):Bool {
		var mappingId:String = Type.getClassName(type) + '|' + name;
		return getProvider(mappingId, true) != null;
	}

	public function satisfiesDirectly(type:Class<Dynamic>, name:String = ''):Bool {
		return hasDirectMapping(type, name) || getDefaultProvider(Type.getClassName(type) + '|' + name, false) != null;
	}

	public function getMapping(type:Class<Dynamic>, name:String = ''):InjectionMapping {
		var mappingId:String = Type.getClassName(type) + '|' + name;
		var mapping:InjectionMapping = _mappings.get(mappingId);
		if (mapping == null) {
			throw 'Error while retrieving an injector mapping: ' + 'No mapping defined for dependency ' + mappingId;
		}
		return mapping;
	}

	public function hasManagedInstance(instance:Dynamic):Bool {
		return _managedObjects.exists(UID.instanceID(instance));
	}

	public function injectInto(target:Dynamic):Void {
		#if (haxe_ver >= 3.40)
		var type:Class<Dynamic> = Type.getClass(target);
		#else
		var type:Class<Dynamic> = _reflector.getClass(target);
		#end

		applyInjectionPoints(target, type, _classDescriptor.getDescription(type));
	}

	public function getInstance(type:Class<Dynamic>, name:String = '', targetType:Class<Dynamic> = null):Dynamic {
		var mappingId:String = Type.getClassName(type) + '|' + name;
		var provider:DependencyProvider;
		if (getProvider(mappingId) != null) {
			provider = getProvider(mappingId);
		} else {
			provider = getDefaultProvider(mappingId, true);
		}
		if (provider != null) {
			var ctor:ConstructorInjectionPoint = _classDescriptor.getDescription(type).ctor;
			var returnVal;
			if (ctor != null)
				returnVal = provider.apply(targetType, this, ctor.injectParameters);
			else
				returnVal = provider.apply(targetType, this, null);
			return returnVal;
		}

		var fallbackMessage:String;
		if (this.fallbackProvider != null) {
			fallbackMessage = "the fallbackProvider, '" + this.fallbackProvider + "', was unable to fulfill this request.";
		} else {
			fallbackMessage = "the injector has no fallbackProvider.";
		}

		throw 'No mapping found for request ' + mappingId + ' and ' + fallbackMessage;
	}

	public function getOrCreateNewInstance(type:Class<Dynamic>):Dynamic {
		var _satisfies = satisfies(type);
		if (_satisfies)
			return getInstance(type);
		else {
			return instantiateUnmapped(type);
		}
	}

	public function instantiateUnmapped(type:Class<Dynamic>):Dynamic {
		if (!canBeInstantiated(type)) {
			throw "Can't instantiate interface " + Type.getClassName(type);
		}

		var description:TypeDescription = _classDescriptor.getDescription(type);
		var instance:Dynamic = description.ctor.createInstance(type, this);
		if (hasEventListener(InjectionEvent.POST_INSTANTIATE)) {
			dispatchEvent(new InjectionEvent(InjectionEvent.POST_INSTANTIATE, instance, type));
		}
		applyInjectionPoints(instance, type, description);
		return instance;
	}

	public function destroyInstance(instance:Dynamic):Void {
		_managedObjects.remove(UID.clearInstanceID(instance));

		#if (haxe_ver >= 3.40)
		var type:Class<Dynamic> = Type.getClass(instance);
		#else
		var type:Class<Dynamic> = _reflector.getClass(instance);
		#end

		var typeDescription:TypeDescription = getTypeDescription(type);
		var preDestroyHook:PreDestroyInjectionPoint = typeDescription.preDestroyMethods;
		while (preDestroyHook != null) {
			preDestroyHook.applyInjection(instance, type, this);
			preDestroyHook = cast(preDestroyHook.next, PreDestroyInjectionPoint);
		}
		// TODO: TEST
		/*for (var preDestroyHook:PreDestroyInjectionPoint = typeDescription.preDestroyMethods; preDestroyHook; preDestroyHook = PreDestroyInjectionPoint(preDestroyHook.next))
			{
				preDestroyHook.applyInjection(instance, type, this);
		}*/
	}

	public function teardown():Void {
		for (mapping in _mappings) {
			mapping.getProvider().destroy();
		}
		var objectsToRemove:Array<Dynamic> = new Array<Dynamic>();
		var fields;

		for (instance in _managedObjects) {
			if (instance)
				objectsToRemove.push(instance);
		}

		while (objectsToRemove.length > 0) {
			destroyInstance(objectsToRemove.pop());
		}
		fields = Reflect.fields(providerMappings);
		for (mappingId in fields) {
			providerMappings.remove(mappingId);
		}
		_mappings = new Map<String, InjectionMapping>();
		_mappingsInProcess = new Map<String, Bool>();
		_managedObjects = new Map<String, Dynamic>();
		this.fallbackProvider = null;
		this.blockParentFallbackProvider = false;
	}

	public function createChildInjector(applicationDomain:ApplicationDomain = null):Injector {
		var injector:Injector = new Injector();
		if (applicationDomain != null)
			injector.applicationDomain = applicationDomain;
		else
			injector.applicationDomain = this.applicationDomain;
		injector.parentInjector = this;
		return injector;
	}

	public function addTypeDescription(type:Class<Dynamic>, description:TypeDescription):Void {
		_classDescriptor.addDescription(type, description);
	}

	public function getTypeDescription(type:Class<Dynamic>):TypeDescription {
		return _reflector.describeInjections(type);
	}

	public function hasMapping(type:Class<Dynamic>, name:String = ''):Bool {
		return getProvider(Type.getClassName(type) + '|' + name) != null;
	}

	public function hasDirectMapping(type:Class<Dynamic>, name:String = ''):Bool {
		return _mappings.exists(Type.getClassName(type) + '|' + name);
	}

	//----------------------             Internal Methods               ----------------------//
	public static function purgeInjectionPointsCache():Void {
		INJECTION_POINTS_CACHE = new Map<String, TypeDescription>();
	}

	public function canBeInstantiated(type:Class<Dynamic>):Bool {
		var description:TypeDescription = _classDescriptor.getDescription(type);
		return description.ctor != null;
	}

	public function getProvider(mappingId:String, fallbackToDefault:Bool = true):DependencyProvider {
		var softProvider:DependencyProvider = null;
		var injector:Injector = this;

		while (injector != null) {
			var provider:DependencyProvider = injector.providerMappings[mappingId];

			if (provider != null) {
				if (Std.isOfType(provider, SoftDependencyProvider)) {
					softProvider = provider;
					injector = injector.parentInjector;
					continue;
				}
				if (Std.isOfType(provider, LocalOnlyProvider) && injector != this) {
					injector = injector.parentInjector;
					continue;
				}

				return provider;
			}
			injector = injector.parentInjector;
		}
		if (softProvider != null) {
			return softProvider;
		}
		if (fallbackToDefault) {
			return getDefaultProvider(mappingId, true);
		} else {
			return null;
		}
	}

	public function getDefaultProvider(mappingId:String, consultParents:Bool):DependencyProvider {
		// No meaningful way to automatically create base types without names
		if (_baseTypes.indexOf(mappingId) > -1) {
			return null;
		}

		if (this.fallbackProvider != null && this.fallbackProvider.prepareNextRequest(mappingId)) {
			return this.fallbackProvider;
		}
		if (consultParents && this.blockParentFallbackProvider && this.parentInjector != null) {
			return this.parentInjector.getDefaultProvider(mappingId, consultParents);
		}
		return null;
	}

	//----------------------         Private / Protected Methods        ----------------------//
	private function createMapping(type:Class<Dynamic>, name:String, mappingId:String):InjectionMapping {
		if (_mappingsInProcess.get(mappingId)) {
			throw "Can't change a mapping from inside a listener to it's creation event";
		}
		_mappingsInProcess.set(mappingId, true);

		hasEventListener(MappingEvent.PRE_MAPPING_CREATE) && dispatchEvent(new MappingEvent(MappingEvent.PRE_MAPPING_CREATE, type, name, null));

		var mapping:InjectionMapping = new InjectionMapping(this, type, name, mappingId);
		_mappings.set(mappingId, mapping);

		var sealKey:Dynamic = mapping.seal();
		hasEventListener(MappingEvent.POST_MAPPING_CREATE) && dispatchEvent(new MappingEvent(MappingEvent.POST_MAPPING_CREATE, type, name, mapping));

		_mappingsInProcess.remove(mappingId);
		mapping.unseal(sealKey);
		return mapping;
	}
	private function applyInjectionPoints(target:Dynamic, targetType:Class<Dynamic>, description:TypeDescription):Void {
		var injectionPoint = description.injectionPoints;
		if (hasEventListener(InjectionEvent.PRE_CONSTRUCT)) {
			dispatchEvent(new InjectionEvent(InjectionEvent.PRE_CONSTRUCT, target, targetType));
		}
		while (injectionPoint != null) {
			injectionPoint.applyInjection(target, targetType, this);
			injectionPoint = injectionPoint.next;
		}
		if (description.preDestroyMethods != null) {
			_managedObjects.set(UID.instanceID(target), target);
		}
		hasEventListener(InjectionEvent.POST_CONSTRUCT) && dispatchEvent(new InjectionEvent(InjectionEvent.POST_CONSTRUCT, target, targetType));
	}
}
