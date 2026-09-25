package eva.ext.viewProcessorMap.impl;

import eva.ext.matching.ITypeFilter;
import eva.ext.viewProcessorMap.dsl.IViewProcessorMapper;
import eva.ext.viewProcessorMap.dsl.IViewProcessorMapping;
import eva.ext.viewProcessorMap.dsl.IViewProcessorMappingConfig;
import eva.ext.viewProcessorMap.dsl.IViewProcessorUnmapper;

@:keepSub
class ViewProcessorMapper implements IViewProcessorMapper implements IViewProcessorUnmapper {
	var _mappings = new Map<String, Dynamic>();
	var _handler:IViewProcessorViewHandler;
	var _matcher:ITypeFilter;

	public function new(matcher:ITypeFilter, handler:IViewProcessorViewHandler) {
		_handler = handler;
		_matcher = matcher;
	}

	public function toProcess(processClassOrInstance:Dynamic):IViewProcessorMappingConfig {
		var mapping:IViewProcessorMapping = _mappings[processClassOrInstance];
		return (mapping != null) ? overwriteMapping(mapping, processClassOrInstance) : createMapping(processClassOrInstance);
	}

	public function toInjection():IViewProcessorMappingConfig {
		return toProcess(ViewInjectionProcessor);
	}

	/**
	 * @inheritDoc
	 */
	public function toNoProcess():IViewProcessorMappingConfig {
		return toProcess(NullProcessor);
	}

	/**
	 * @inheritDoc
	 */
	public function fromProcess(processorClassOrInstance:Dynamic):Void {
		var mapping:IViewProcessorMapping = _mappings[processorClassOrInstance];
		if (mapping != null)
			deleteMapping(mapping);
	}

	/**
	 * @inheritDoc
	 */
	public function fromAll():Void {
		for (processor in _mappings) {
			fromProcess(processor);
		}
	}

	/**
	 * @inheritDoc
	 */
	public function fromNoProcess():Void {
		fromProcess(NullProcessor);
	}

	/**
	 * @inheritDoc
	 */
	public function fromInjection():Void {
		fromProcess(ViewInjectionProcessor);
	}

	/*============================================================================*/
	/* Functions                                                          */
	/*============================================================================*/
	function createMapping(processor:Dynamic):ViewProcessorMapping {
		var mapping:ViewProcessorMapping = new ViewProcessorMapping(_matcher, processor);
		_handler.addMapping(mapping);
		_mappings[processor] = mapping;
		trace('{0} mapped to {1}', [_matcher, mapping]);
		return mapping;
	}

	function deleteMapping(mapping:IViewProcessorMapping):Void {
		_handler.removeMapping(mapping);
		_mappings.remove(mapping.processor);
		trace('{0} unmapped from {1}', [_matcher, mapping]);
	}

	function overwriteMapping(mapping:IViewProcessorMapping, processClassOrInstance:Dynamic):IViewProcessorMappingConfig {
		trace('{0} is already mapped to {1}.\n'
			+ 'If you have overridden this mapping intentionally you can use "unmap()" '
			+ 'prior to your replacement mapping in order to avoid seeing this message.\n',
			[_matcher, mapping]);

		deleteMapping(mapping);
		return createMapping(processClassOrInstance);
	}
}
