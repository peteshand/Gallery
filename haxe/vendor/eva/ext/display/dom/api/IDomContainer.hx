package eva.ext.display.dom.api;

import signals.Signal1;
import js.html.Element;
import eva.ext.display.dom.impl.*;

interface IDomContainer {
	var parent(default, null):DomContainer;
	var element:Element;
	var children:Array<DomContainer>;
	var hidePolicy:HidePolicy;
	var removeOnTransition(get, set):Bool;
	var onAddChild:Signal1<IDomContainer>;
	var onRemoveChild:Signal1<IDomContainer>;
	function initialize():Void;
}
