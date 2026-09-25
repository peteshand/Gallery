package inject.mapping;

import inject.provider.DependencyProvider;

@:keepSub
interface ProviderlessMapping {
	function toType(type:Class<Dynamic>):UnsealedMapping;
	function toValue(value:Dynamic, autoInject:Bool = false, destroyOnUnmap:Bool = false):UnsealedMapping;
	function toSingleton(type:Class<Dynamic>, initializeImmediately:Bool = false):UnsealedMapping;
	function asSingleton(initializeImmediately:Bool = false):UnsealedMapping;
	function toProvider(provider:DependencyProvider):UnsealedMapping;
	function seal():Dynamic;
}
