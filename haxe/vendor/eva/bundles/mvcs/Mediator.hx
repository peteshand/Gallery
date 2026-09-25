package eva.bundles.mvcs;

import polyfill.events.Event;
import polyfill.events.IEventDispatcher;
import inject.utils.DescribedType;
import eva.ext.localEventMap.api.IEventMap;
import eva.ext.mediatorMap.api.IMediator;

@:keepSub
class Mediator implements DescribedType implements IMediator {
	@inject public var eventMap:IEventMap;
	@inject public var eventDispatcher:IEventDispatcher;
	public var viewComponent(null, default):Dynamic;

	public function initialize():Void {}

	public function destroy():Void {}

	public inline function postDestroy():Void {
		eventMap.unmapListeners();
	}

	private inline function addViewListener(eventString:String, listener:Dynamic, eventClass:Class<Dynamic> = null):Void {
		eventMap.mapListener(cast(viewComponent, IEventDispatcher), eventString, listener, eventClass);
	}

	private inline function addContextListener(eventString:String, listener:Dynamic, eventClass:Class<Dynamic> = null):Void {
		eventMap.mapListener(eventDispatcher, eventString, listener, eventClass);
	}

	private inline function removeViewListener(eventString:String, listener:Dynamic, eventClass:Class<Dynamic> = null):Void {
		eventMap.unmapListener(cast(viewComponent, IEventDispatcher), eventString, listener, eventClass);
	}

	private inline function removeContextListener(eventString:String, listener:Dynamic, eventClass:Class<Dynamic> = null):Void {
		eventMap.unmapListener(eventDispatcher, eventString, listener, eventClass);
	}

	private inline function dispatch(event:Event):Void {
		if (eventDispatcher.hasEventListener(event.type))
			eventDispatcher.dispatchEvent(event);
	}
}
