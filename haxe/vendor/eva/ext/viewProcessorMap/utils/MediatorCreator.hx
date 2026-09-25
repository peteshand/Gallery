package eva.ext.viewProcessorMap.utils;

import inject.utils.CallProxy;
import inject.utils.UID;
import eva.IInjector;

@:keepSub
class MediatorCreator {
	var _mediatorClass:Class<Dynamic>;
	var _createdMediatorsByView = new Map<String, Dynamic>();

	public function new(mediatorClass:Class<Dynamic>) {
		_mediatorClass = mediatorClass;
	}

	public function process(view:Dynamic, type:Class<Dynamic>, injector:IInjector):Void {
		trace("view = " + view);
		if (_createdMediatorsByView[UID.classID(view)]) {
			return;
		}
		var mediator:Dynamic = injector.instantiateUnmapped(_mediatorClass);
		_createdMediatorsByView[UID.classID(view)] = mediator;
		initializeMediator(view, mediator);
	}

	public function unprocess(view:Dynamic, type:Class<Dynamic>, injector:IInjector):Void {
		if (_createdMediatorsByView[UID.classID(view)]) {
			destroyMediator(_createdMediatorsByView[UID.classID(view)]);
			_createdMediatorsByView.remove(UID.classID(view));
		}
	}

	function initializeMediator(view:Dynamic, mediator:Dynamic):Void {
		if (CallProxy.hasField(mediator, 'preInitialize')) {
			var preInitialize = Reflect.getProperty(mediator, 'preInitialize');
			if (preInitialize != null)
				preInitialize();
		}

		if (CallProxy.hasField(mediator, 'viewComponent'))
			mediator.viewComponent = view;

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
