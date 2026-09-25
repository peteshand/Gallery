package inject.mapping;

import inject.Injector;
import inject.provider.ClassProvider;
import inject.provider.DependencyProvider;
import inject.provider.ForwardingProvider;
import inject.provider.InjectorUsingProvider;
import inject.provider.LocalOnlyProvider;
import inject.provider.SingletonProvider;
import inject.provider.SoftDependencyProvider;
import inject.provider.ValueProvider;

@:keepSub
class InjectionMapping implements ProviderlessMapping implements UnsealedMapping {
	var _type:Class<Dynamic>;
	var _name:String;
	var _mappingId:String;
	var _creatingInjector:Injector;
	var _defaultProviderSet:Bool;

	var _overridingInjector:Injector;
	var _soft:Bool;
	var _local:Bool;
	var _sealed:Bool;
	var _sealKey:Dynamic;

	public function new(creatingInjector:Injector, type:Class<Dynamic>, name:String, mappingId:String) {
		_creatingInjector = creatingInjector;
		_type = type;
		_name = name;
		_mappingId = mappingId;
		_defaultProviderSet = true;
		mapProvider(new ClassProvider(type));
	}

	public function asSingleton(initializeImmediately:Bool = false):UnsealedMapping {
		toSingleton(_type, initializeImmediately);
		return this;
	}

	public function toType(type:Class<Dynamic>):UnsealedMapping {
		toProvider(new ClassProvider(type));
		return this;
	}

	public function toSingleton(type:Class<Dynamic>, initializeImmediately:Bool = false):UnsealedMapping {
		toProvider(new SingletonProvider(type, _creatingInjector));
		if (initializeImmediately) {
			_creatingInjector.getInstance(_type, _name);
		}
		return this;
	}

	public function toValue(value:Dynamic, autoInject:Bool = false, destroyOnUnmap:Bool = false):UnsealedMapping {
		toProvider(new ValueProvider(value, destroyOnUnmap ? _creatingInjector : null));
		if (autoInject) {
			_creatingInjector.injectInto(value);
		}
		return this;
	}

	public function toProvider(provider:DependencyProvider):UnsealedMapping {
		if (_sealed)
			throwSealedError();
		if (hasProvider() && provider != null && !_defaultProviderSet) {
			_creatingInjector.hasEventListener(MappingEvent.MAPPING_OVERRIDE)
			&& _creatingInjector.dispatchEvent(new MappingEvent(MappingEvent.MAPPING_OVERRIDE, _type, _name, this));
		} dispatchPreChangeEvent();
		_defaultProviderSet = false;
		mapProvider(provider);
		dispatchPostChangeEvent();
		return this;
	}

	public function toProviderOf(type:Class<Dynamic>, name:String = ''):UnsealedMapping {
		var provider:DependencyProvider = _creatingInjector.getMapping(type, name).getProvider();
		toProvider(provider);
		return this;
	}

	public function softly():ProviderlessMapping {
		if (_sealed)
			throwSealedError();
		if (!_soft) {
			var provider:DependencyProvider = getProvider();
			dispatchPreChangeEvent();
			_soft = true;
			mapProvider(provider);
			dispatchPostChangeEvent();
		}
		return this;
	}

	public function locally():ProviderlessMapping {
		if (_sealed)
			throwSealedError();
		if (_local) {
			return this;
		}
		var provider:DependencyProvider = getProvider();
		dispatchPreChangeEvent();
		_local = true;
		mapProvider(provider);
		dispatchPostChangeEvent();
		return this;
	}

	public function seal():Dynamic {
		if (_sealed) {
			throw 'Mapping is already sealed.';
		}
		_sealed = true;
		_sealKey = {};
		return _sealKey;
	}

	public function unseal(key:Dynamic):InjectionMapping {
		if (!_sealed) {
			throw "Can't unseal a non-sealed mapping.";
		}
		if (key != _sealKey) {
			throw "Can't unseal mapping without the correct key.";
		}
		_sealed = false;
		_sealKey = null;
		return this;
	}

	public var isSealed(get, null):Bool;

	public function get_isSealed():Bool {
		return _sealed;
	}

	public function hasProvider():Bool {
		if (_creatingInjector.providerMappings[_mappingId] == null)
			return false;
		return true;
	}

	public function getProvider():DependencyProvider {
		var provider:DependencyProvider = _creatingInjector.providerMappings[_mappingId];
		while (Std.isOfType(provider, ForwardingProvider)) {
			provider = cast(provider, ForwardingProvider).provider;
		}
		return provider;
	}

	public function setInjector(injector:Injector):InjectionMapping {
		if (_sealed)
			throwSealedError();

		if (injector == _overridingInjector) {
			return this;
		}
		var provider:DependencyProvider = getProvider();
		_overridingInjector = injector;
		mapProvider(provider);
		return this;
	}

	function mapProvider(provider:DependencyProvider):Void {
		if (_soft) {
			provider = new SoftDependencyProvider(provider);
		}
		if (_local) {
			provider = new LocalOnlyProvider(provider);
		}
		if (_overridingInjector != null) {
			provider = new InjectorUsingProvider(_overridingInjector, provider);
		}

		_creatingInjector.providerMappings[_mappingId] = provider;
	}

	function throwSealedError():Void {
		throw "Can't change a sealed mapping";
	}

	function dispatchPreChangeEvent():Void {
		_creatingInjector.hasEventListener(MappingEvent.PRE_MAPPING_CHANGE) && _creatingInjector.dispatchEvent(new MappingEvent(MappingEvent.PRE_MAPPING_CHANGE,
			_type, _name, this));

	}
	function dispatchPostChangeEvent():Void {
		_creatingInjector.hasEventListener(MappingEvent.POST_MAPPING_CHANGE) && _creatingInjector.dispatchEvent(new MappingEvent(MappingEvent.POST_MAPPING_CHANGE,
			_type, _name, this));
	}
}
