package inject.provider;

@:keepSub
interface FallbackDependencyProvider extends DependencyProvider {
	function prepareNextRequest(mappingId:String):Bool;
}
