package eva.ext.contextView;

import openfl.display.DisplayObjectContainer;
import polyfill.events.Event;
import eva.ext.matching.InstanceOfType;
import eva.IContext;
import eva.IExtension;

@:keepSub
class StageSyncExtension implements IExtension {
	var _context:IContext;
	var _contextView:DisplayObjectContainer;

	public function extend(context:IContext):Void {
		_context = context;
		_context.addConfigHandler(InstanceOfType.call(ContextView), handleContextView);
	}

	function handleContextView(contextView:ContextView):Void {
		if (_contextView != null) {
			trace('A contextView has already been installed, ignoring {0}', [contextView.view]);
			return;
		}
		_contextView = contextView.view;
		if (_contextView.stage != null) {
			initializeContext();
		} else {
			trace("Context view is not yet on stage. Waiting...");
			_contextView.addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
		}
	}

	function onAddedToStage(event:Event):Void {
		_contextView.removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
		initializeContext();
	}

	function initializeContext():Void {
		trace("Context view is now on stage. Initializing context...");

		_context.initialize();
		_contextView.addEventListener(Event.REMOVED_FROM_STAGE, onRemovedFromStage);
	}

	function onRemovedFromStage(event:Event):Void {
		trace("Context view has left the stage. Destroying context...");
		_contextView.removeEventListener(Event.REMOVED_FROM_STAGE, onRemovedFromStage);
		_context.destroy();
	}
}
