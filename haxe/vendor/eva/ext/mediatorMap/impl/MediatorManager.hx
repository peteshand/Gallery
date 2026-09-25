package eva.ext.mediatorMap.impl;

import polyfill.events.Event;
import polyfill.events.EventDispatcher;
import inject.utils.CallProxy;
import eva.ext.mediatorMap.api.IMediatorMapping;

@:keepSub
class MediatorManager {
	static var UIComponentClass:Class<Dynamic>;
	static var flexAvailable:Bool = false;

	public static var CREATION_COMPLETE:String = "creationComplete";

	var _factory:MediatorFactory;

	public function new(factory:MediatorFactory) {
		_factory = factory;
	}

	public function addMediator(mediator:Dynamic, item:Dynamic, mapping:IMediatorMapping):Void {
		var eventDispatcher:EventDispatcher = null;
		if (Std.isOfType(item, EventDispatcher)) {
			eventDispatcher = cast(item, EventDispatcher);
		}

		// Watch Display Dynamic for removal
		if (eventDispatcher != null && mapping.autoRemoveEnabled)
			eventDispatcher.addEventListener(Event.REMOVED_FROM_STAGE, onRemovedFromStage);

		// Synchronize with item life-cycle
		if (itemInitialized(item)) {
			initializeMediator(mediator, item);
		} else {
			var mediatorManagerAddMediator:MediatorManagerAddMediator = new MediatorManagerAddMediator(initializeMediator, _factory, eventDispatcher,
				mediator, item, mapping);
			eventDispatcher.addEventListener(MediatorManager.CREATION_COMPLETE, mediatorManagerAddMediator.creationComplete);
		}
	}

	public function removeMediator(mediator:Dynamic, item:Dynamic, mapping:IMediatorMapping):Void {
		if (Std.isOfType(item, EventDispatcher))
			cast(item, EventDispatcher).removeEventListener(Event.REMOVED_FROM_STAGE, onRemovedFromStage);

		if (itemInitialized(item))
			destroyMediator(mediator);
	}

	function onRemovedFromStage(event:Event):Void {
		_factory.removeMediators(event.target);
	}

	function itemInitialized(item:Dynamic):Bool {
		if (flexAvailable && (Std.isOfType(item, UIComponentClass)) && !CallProxy.hasField(item, 'initialized'))
			return false;
		return true;
	}

	function initializeMediator(mediator:Dynamic, mediatedItem:Dynamic):Void {
		if (CallProxy.hasField(mediator, 'preInitialize'))
			mediator.preInitialize();

		if (CallProxy.hasField(mediator, 'viewComponent'))
			mediator.viewComponent = mediatedItem;

		if (CallProxy.hasField(mediator, 'initialize'))
			mediator.initialize();

		if (CallProxy.hasField(mediator, 'postInitialize'))
			mediator.postInitialize();
	}

	function destroyMediator(mediator:Dynamic):Void {
		if (CallProxy.hasField(mediator, 'preDestroy'))
			mediator.preDestroy();

		if (CallProxy.hasField(mediator, 'destroy'))
			mediator.destroy();

		if (CallProxy.hasField(mediator, 'viewComponent'))
			mediator.viewComponent = null;

		if (CallProxy.hasField(mediator, 'postDestroy'))
			mediator.postDestroy();
	}
}

@:keepSub
class MediatorManagerAddMediator {
	var eventDispatcher:EventDispatcher;
	var mediator:Dynamic;
	var item:Dynamic;
	var mapping:IMediatorMapping;
	var _factory:MediatorFactory;
	var initializeMediator:Dynamic;

	public function new(initializeMediator:Dynamic->Dynamic->Void, _factory:MediatorFactory, eventDispatcher:EventDispatcher, mediator:Dynamic, item:Dynamic,
			mapping:IMediatorMapping) {
		this.initializeMediator = initializeMediator;
		this._factory = _factory;
		this.mapping = mapping;
		this.item = item;
		this.mediator = mediator;
		this.eventDispatcher = eventDispatcher;
	}

	public function creationComplete(e:Event):Void {
		eventDispatcher.removeEventListener(MediatorManager.CREATION_COMPLETE, creationComplete);
		// Ensure that we haven't been removed in the meantime
		if (_factory.getMediator(item, mapping) == mediator) {
			initializeMediator(mediator, item);
		}
	}
}
