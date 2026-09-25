package inject;

import polyfill.events.Event;

@:keepSub
class InjectionEvent extends Event {
	public static var POST_INSTANTIATE:String = 'postInstantiate';
	public static var PRE_CONSTRUCT:String = 'preConstruct';
	public static var POST_CONSTRUCT:String = 'postConstruct';

	public var instance:Dynamic;
	public var instanceType:Class<Dynamic>;

	public function new(type:String, instance:Dynamic, instanceType:Class<Dynamic>) {
		super(type);
		this.instance = instance;
		this.instanceType = instanceType;
	}

	override public function clone():Event {
		return new InjectionEvent(type, instance, instanceType);
	}
}
