package inject.provider;

@:keepSub
class SoftDependencyProvider extends ForwardingProvider {
	public function new(provider:DependencyProvider) {
		super(provider);
	}
}
