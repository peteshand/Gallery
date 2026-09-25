package eva.ext.contextView;

import eva.ext.matching.InstanceOfType;
import eva.IContext;
import eva.IExtension;
import eva.IInjector;

@:keepSub
class ContextViewExtension implements IExtension {
	private var _injector:IInjector;

	public function extend(context:IContext):Void {
		_injector = context.injector;
		context.beforeInitializing(beforeInitializing);
		context.addConfigHandler(InstanceOfType.call(ContextView), handleContextView);
	}

	/*============================================================================*/
	/* Private Functions                                                          */
	/*============================================================================*/
	private function handleContextView(contextView:ContextView):Void {
		if (_injector.hasDirectMapping(ContextView)) {
			trace('A contextView has already been installed, ignoring {0}', [contextView.view]);
		} else {
			trace("Mapping {0} as contextView", [contextView.view]);
			_injector.map(ContextView).toValue(contextView);
		}
	}

	private function beforeInitializing():Void {
		if (!_injector.hasDirectMapping(ContextView)) {
			trace("A ContextView must be installed if you install the ContextViewExtension.");
		}
	}
}
