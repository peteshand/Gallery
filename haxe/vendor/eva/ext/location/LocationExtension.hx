package eva.ext.location;

import location.Location;
import inject.utils.DescribedType;
import eva.ext.modelMap.api.IModelMap;
import eva.IExtension;
import eva.IContext;

class LocationExtension implements DescribedType implements IExtension {
	public function new() {}

	public function extend(context:IContext):Void {
		var modelMap:IModelMap = context.injector.getInstance(IModelMap);
		if (modelMap == null) {
			context.injector.map(Location).toValue(Location.instance);
		} else {
			modelMap.map(Location, "scene").toValue(Location.instance);
		}
	}
}
