package inject.utils;

import inject.reflection.Reflector;
import inject.def.TypeDescription;

@:keepSub
class TypeDescriptor {
	public var _descriptionsCache:Map<String, TypeDescription>;

	var _reflector:Reflector;

	public function new(reflector:Reflector, descriptionsCache:Map<String, TypeDescription>) {
		_descriptionsCache = descriptionsCache;
		_reflector = reflector;
	}

	public function getDescription(type:Class<Dynamic>):TypeDescription {
		var id = UID.classID(type);

		if (_descriptionsCache[id] == null) {
			_descriptionsCache[id] = _reflector.describeInjections(type);
		}
		return _descriptionsCache[id];
	}

	public function addDescription(type:Class<Dynamic>, description:TypeDescription):Void {
		_descriptionsCache[UID.classID(type)] = description;
	}
}
