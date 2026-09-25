package eva.ext.viewManager.impl;

import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import polyfill.events.Event;

@:keepSub
class StageObserver {
	var _filter = ~/^mx\.|^spark\.|^flash\./;
	var _registry:ContainerRegistry;

	public function new(containerRegistry:ContainerRegistry) {
		_registry = containerRegistry;
		// We only care about roots
		_registry.addEventListener(ContainerRegistryEvent.ROOT_CONTAINER_ADD, onRootContainerAdd);
		_registry.addEventListener(ContainerRegistryEvent.ROOT_CONTAINER_REMOVE, onRootContainerRemove);
		// We might have arrived late on the scene
		for (binding in _registry.rootBindings) {
			addRootListener(binding.container);
		}
	}

	public function destroy():Void {
		_registry.removeEventListener(ContainerRegistryEvent.ROOT_CONTAINER_ADD, onRootContainerAdd);
		_registry.removeEventListener(ContainerRegistryEvent.ROOT_CONTAINER_REMOVE, onRootContainerRemove);
		for (binding in _registry.rootBindings) {
			removeRootListener(binding.container);
		}
	}

	function onRootContainerAdd(event:ContainerRegistryEvent):Void {
		addRootListener(event.container);
	}

	function onRootContainerRemove(event:ContainerRegistryEvent):Void {
		removeRootListener(event.container);
	}

	function addRootListener(container:DisplayObjectContainer):Void {
		// The magical, but extremely expensive, capture-phase ADDED listener
		container.addEventListener(Event.ADDED_TO_STAGE, onViewAddedToStage, true);
		// Watch the root container itself - nobody else is going to pick it up!
		container.addEventListener(Event.ADDED_TO_STAGE, onContainerRootAddedToStage);
	}

	function onViewAddedToStage(event:Event):Void {
		var view:DisplayObject = cast(event.target, DisplayObject);
		addView(view);
	}

	function onContainerRootAddedToStage(event:Event):Void {
		var container:DisplayObjectContainer = cast(event.target, DisplayObjectContainer);
		container.removeEventListener(Event.ADDED_TO_STAGE, onContainerRootAddedToStage);
		var type:Class<Dynamic> = Type.getClass(container);
		var binding:ContainerBinding = _registry.getBinding(container);
		if (binding != null)
			binding.handleView(container, type);
	}

	function removeRootListener(container:DisplayObjectContainer):Void {
		container.removeEventListener(Event.ADDED_TO_STAGE, onViewAddedToStage, true);
		container.removeEventListener(Event.ADDED_TO_STAGE, onContainerRootAddedToStage);
	}

	function addView(view:DisplayObject):Void {
		// Question: would it be worth caching QCNs by view in a weak Map<Dynamic,Dynamic>,
		// to avoid Type.getClassName() cost?
		var qcn:String = Type.getClassName(Type.getClass(view));
		// CHECK
		// var filtered:Bool = _filter.test(qcn);
		var filtered:Bool = _filter.match(qcn);
		if (filtered)
			return;
		var type:Class<Dynamic> = Type.getClass(view);
		// Walk upwards from the nearest binding
		var binding:ContainerBinding = _registry.findParentBinding(view);
		while (binding != null) {
			binding.handleView(view, type);
			binding = binding.parent;
		}
	}
}
