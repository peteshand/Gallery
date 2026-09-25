package eva.ext.display.dom.impl;

#if macro
class DomContainer {}
#else
import signals.Signal1;
import js.html.*;
import eva.ext.display.dom.api.IDomContainer;
import js.Browser;
import js.Browser.document;
import js.Browser.window;

class DomContainer implements IDomContainer {
	public var element:Element;
	public var view(get, null):Element;
	public var id(get, set):String;
	public var className(get, set):String;
	public var style(get, null):CSSStyleDeclaration;
	public var innerText(get, set):String;
	public var innerHTML(get, set):String;
	public var outerHTML(get, set):String;
	public var textContent(get, set):String;
	public var numChildren(get, null):Int;

	var _onPress:Signal1<MouseEvent>;
	var _onRelease:Signal1<MouseEvent>;
	var _onOver:Signal1<MouseEvent>;
	var _onOut:Signal1<MouseEvent>;
	var _dblClick:Signal1<MouseEvent>;

	public var onPress(get, null):Signal1<MouseEvent>;
	public var onRelease(get, null):Signal1<MouseEvent>;
	public var onOver(get, null):Signal1<MouseEvent>;
	public var onOut(get, null):Signal1<MouseEvent>;
	public var dblClick(get, null):Signal1<MouseEvent>;
	public var onAddChild = new Signal1<IDomContainer>();
	public var onRemoveChild = new Signal1<IDomContainer>();
	public var children:Array<DomContainer> = [];
	public var removeOnTransition(get, set):Bool;
	public var hidePolicy:HidePolicy = HidePolicy.REMOVE;

	var parentElement:Element;
	var added:Bool = false;

	// var document(get, null):HTMLDocument;
	// var window(get, null):Window;
	// var parentElements = new Map<Element, Element>();
	@:isVar public var parent(default, null):DomContainer;
	@:isVar public var alpha(default, set):Float = 1;
	@:isVar public var visible(default, set):Null<Bool> = true;

	public var ignoreAddChild:Bool = false;

	public function new(?className:String, ?element:Element = null) {
		if (element == null) {
			element = Browser.document.createDivElement();
		}

		this.element = element;
		if (this.element != null) {
			untyped this.element.container = this;
		}
		if (className != null) {
			this.className = className;
		}
	}

	public function initialize():Void {
		//
	}

	public function addChild(child:DomContainer):Void {
		children.remove(child);
		children.push(child);

		child.parent = this;
		child.parentElement = element;
		if (child.visible) {
			child.added = true;
			if (!child.ignoreAddChild){
				element.appendChild(child.element);
			}
			
		}
		onAddChild.dispatch(child);
	}

	public function removeChild(child:DomContainer):Void {
		children.remove(child);
		try {
			if (child.element.parentNode != null) {
				child.element.parentNode.removeChild(child.element);
			}
			child.parentElement = null;
			child.added = false;
		} catch (e:Dynamic) {
			trace(e);
		}
		onRemoveChild.dispatch(child);
	}

	public function dispose():Void {
		for (child in children) {
			child.dispose();
		}
	}

	public function addElement(element:js.html.Element):Void {
		// element.parentElement = element;
		this.element.appendChild(element);
	}

	public function removeElement(element:js.html.Element):Void {
		try {
			// element.parentElement = null;
			element.remove();
		} catch (e:Dynamic) {
			trace(e);
		}
	}

	function get_id():String {
		return element.id;
	}

	function set_id(value:String):String {
		if (value == null) {
			element.removeAttribute("id");
		} else {
			element.id = value;
		}
		return value;
	}

	function get_className():String {
		return element.className;
	}

	function set_className(value:String):String {
		if (value == null) {
			element.removeAttribute("class");
		} else {
			element.className = value;
		}
		return value;
	}

	@:keep function get_style():CSSStyleDeclaration {
		return element.style;
	}

	@:keep function get_view():Element {
		return element;
	}

	@:keep function set_alpha(value:Float):Float {
		this.alpha = value;
		this.style.opacity = Std.string(alpha);
		return this.alpha;
	}

	@:keep function set_visible(value:Bool):Bool {
		if (this.visible == value)
			return value;
		this.visible = value;

		if (hidePolicy == HidePolicy.REMOVE) {
			if (parentElement != null) {
				if (visible) {
					if (!added) {
						added = true;
						dispatch(element, 'DOMNodeInserted');
						parentElement.appendChild(element);
					}
				} else {
					if (added) {
						added = false;
						parentElement.removeChild(element);
					}
				}
			}
		} else if (hidePolicy == HidePolicy.VISIBILITY) {
			if (visible) {
				element.style.visibility = 'inherit';
			} else {
				element.style.visibility = 'hidden';
			}
		} else if (hidePolicy == HidePolicy.DISPLAY) {
			if (visible) {
				element.style.display = 'inherit';
			} else {
				element.style.display = 'none';
			}
		}

		return value;
	}

	function dispatch(element:Element, eventStr:String) {
		var event:Event = null;

		try {
			event = new Event(eventStr);
		} catch (e:Dynamic) {
			try {
				event = js.Browser.document.createEvent('Event');
				event.initEvent('eventStr', true, true);
			} catch (e:Dynamic) {
				throw(e);
			}
		}

		if (event != null) {
			element.dispatchEvent(event);
		}

		for (child in element.children) {
			dispatch(child, eventStr);
		}
	}

	function get_innerText():String {
		return element.innerText;
	}

	function set_innerText(value:String):String {
		return element.innerText = value;
	}

	function get_innerHTML():String {
		return element.innerHTML;
	}

	function set_innerHTML(value:String):String {
		if (value != null) {
			value = value.split("\n").join("<br/>");
		}
		return element.innerHTML = value;
	}

	function get_outerHTML():String {
		return element.outerHTML;
	}

	function set_outerHTML(value:String):String {
		return element.outerHTML = value;
	}

	function get_textContent():String {
		return element.textContent;
	}

	function set_textContent(value:String):String {
		return element.textContent = value;
	}

	public function addEventListener(type:String, listener:haxe.Constraints.Function, ?options:haxe.extern.EitherType<AddEventListenerOptions, Bool>,
			?wantsUntrusted:Bool):Void {
		element.addEventListener(type, listener, options, wantsUntrusted);
	}

	public function removeEventListener(type:String, listener:haxe.Constraints.Function, ?options:haxe.extern.EitherType<AddEventListenerOptions, Bool>):Void {
		element.removeEventListener(type, listener, options);
	}

	public function dispatchEvent(event:Event):Void {
		element.dispatchEvent(event);
	}

	function get_numChildren():Int {
		return children.length;
	}

	function getChildByIndex(index:Int):DomContainer {
		return children[index];
	}

	@:keep function get_onPress() {
		if (_onPress == null) {
			_onPress = new Signal1<MouseEvent>();
			element.addEventListener("mousedown", _onPress.dispatch);
		}
		return _onPress;
	}

	@:keep function get_onRelease() {
		if (_onRelease == null) {
			_onRelease = new Signal1<MouseEvent>();
			element.addEventListener("mouseup", _onRelease.dispatch);
		}
		return _onRelease;
	}

	@:keep function get_onOver() {
		if (_onOver == null) {
			_onOver = new Signal1<MouseEvent>();
			element.addEventListener("mouseover", _onOver.dispatch);
		}
		return _onOver;
	}

	@:keep function get_onOut() {
		if (_onOut == null) {
			_onOut = new Signal1<MouseEvent>();
			element.addEventListener("mouseout", _onOut.dispatch);
		}
		return _onOut;
	}

	@:keep function get_dblClick() {
		if (_dblClick == null) {
			_dblClick = new Signal1<MouseEvent>();
			element.addEventListener("dblclick", _dblClick.dispatch);
		}
		return _dblClick;
	}

	function get_document():HTMLDocument {
		return document;
	}

	function get_window():Window {
		return window;
	}

	function get_removeOnTransition():Bool {
		return hidePolicy == HidePolicy.REMOVE;
	}

	function set_removeOnTransition(value:Bool):Bool {
		if (value) {
			hidePolicy = HidePolicy.REMOVE;
		} else {
			hidePolicy = HidePolicy.VISIBILITY;
		}
		return removeOnTransition;
	}
}
#end
