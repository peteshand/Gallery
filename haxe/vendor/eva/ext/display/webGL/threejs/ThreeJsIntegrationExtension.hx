package eva.ext.display.webGL.threejs;

import inject.utils.DescribedType;
import eva.ext.matching.InstanceOfType;
import eva.ext.display.webGL.threejs.api.IThreeJsViewMap;
import eva.ext.display.webGL.threejs.impl.ThreeJsCollection;
import eva.ext.display.webGL.threejs.impl.ThreeJsInitializer;
import eva.ext.display.webGL.threejs.impl.ThreeJsViewMap;
import eva.IContext;
import eva.IExtension;
import inject.utils.UID;

class ThreeJsIntegrationExtension implements DescribedType implements IExtension {
	var _uid:String;
	var _context:IContext;

	public function new() {}

	public function extend(context:IContext):Void {
		_uid = UID.create(ThreeJsIntegrationExtension);

		_context = context;

		_context.addConfigHandler(InstanceOfType.call(ThreeJsCollection), handleThreeJsCollection);
	}

	public function toString():String {
		return _uid;
	}

	function handleThreeJsCollection(threeJsCollection:ThreeJsCollection):Void {
		trace("Mapping provided ThreeJs instances...");
		_context.injector.map(ThreeJsCollection).toValue(threeJsCollection);

		for (view in threeJsCollection.view3Ds) {
			ApplyThreePatch.execute(view.scene);
		}

		_context.injector.map(IThreeJsViewMap).toSingleton(ThreeJsViewMap);
		_context.injector.getInstance(IThreeJsViewMap);
	}
}
