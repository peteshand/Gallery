package inject.provider;

@:keepSub
class LocalOnlyProvider extends ForwardingProvider {
	public function new(provider:DependencyProvider) {
		super(provider);
	}
}
