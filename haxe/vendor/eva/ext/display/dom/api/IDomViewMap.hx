package eva.ext.display.dom.api;

import js.html.Element;

@:keepSub
interface IDomViewMap {
	function initialize():Void;
	function addView(view:IDomContainer):Void;
	function removeView(view:IDomContainer):Void;
}
