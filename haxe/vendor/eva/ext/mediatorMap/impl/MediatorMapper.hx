package eva.ext.mediatorMap.impl;

import inject.utils.UID;
import eva.ext.matching.ITypeFilter;
import eva.ext.mediatorMap.api.IMediatorMapping;
import eva.ext.mediatorMap.dsl.IMediatorConfigurator;
import eva.ext.mediatorMap.dsl.IMediatorMapper;
import eva.ext.mediatorMap.dsl.IMediatorUnmapper;
import eva.bundles.mvcs.Mediator;

@:keepSub
class MediatorMapper implements IMediatorMapper implements IMediatorUnmapper {
	var _mappings = new Map<String, MediatorMapping>();
	var _typeFilter:ITypeFilter;
	var _handler:MediatorViewHandler;

	public function new(typeFilter:ITypeFilter, handler:MediatorViewHandler) {
		_typeFilter = typeFilter;
		_handler = handler;
	}

	public function toMediator(mediatorClass:Class<Mediator>):IMediatorConfigurator {
		var mapping:IMediatorMapping = _mappings.get(UID.classID(mediatorClass));
		return (mapping != null) ? overwriteMapping(mapping) : createMapping(mediatorClass);
	}

	public function fromMediator(mediatorClass:Class<Mediator>):Void {
		var mapping:IMediatorMapping = _mappings.get(UID.classID(mediatorClass));
		if (mapping != null)
			deleteMapping(mapping);
	}

	public function fromAll():Void {
		for (mapping in _mappings.iterator()) {
			deleteMapping(mapping);
		}
	}

	function createMapping(mediatorClass:Class<Mediator>):MediatorMapping {
		var mapping:MediatorMapping = new MediatorMapping(_typeFilter, mediatorClass);
		_handler.addMapping(mapping);
		_mappings.set(UID.classID(mediatorClass), mapping);
		// trace('{0} mapped to {1}', [_typeFilter, mapping]);
		return mapping;
	}

	function deleteMapping(mapping:IMediatorMapping):Void {
		_handler.removeMapping(mapping);
		_mappings.remove(UID.classID(mapping.mediatorClass));
		// trace('{0} unmapped from {1}', [_typeFilter, mapping]);
	}

	function overwriteMapping(mapping:IMediatorMapping):IMediatorConfigurator {
		/*trace('{0} already mapped to {1}\n'
			+ 'If you have overridden this mapping intentionally you can use "unmap()" '
			+ 'prior to your replacement mapping in order to avoid seeing this message.\n',
			[_typeFilter.descriptor, Type.getClassName(mapping.mediatorClass)]); */
		deleteMapping(mapping);
		return createMapping(mapping.mediatorClass);
	}
}

@:coreType abstract ClassMediator from Class<Mediator> to {} {
	@to
	public function toClassMediator():Class<Mediator> {
		return untyped this;
	}
}
