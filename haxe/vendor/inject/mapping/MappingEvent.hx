package inject.mapping;

import polyfill.events.Event;

@:keepSub
class MappingEvent extends Event {
	public static var PRE_MAPPING_CREATE:String = 'preMappingCreate';
	public static var POST_MAPPING_CREATE:String = 'postMappingCreate';
	public static var PRE_MAPPING_CHANGE:String = 'preMappingChange';
	public static var POST_MAPPING_CHANGE:String = 'postMappingChange';
	public static var POST_MAPPING_REMOVE:String = 'postMappingRemove';
	public static var MAPPING_OVERRIDE:String = 'mappingOverride';

	public var mappedType:Class<Dynamic>;
	public var mappedName:String;
	public var mapping:InjectionMapping;

	public function new(type:String, mappedType:Class<Dynamic>, mappedName:String, mapping:InjectionMapping) {
		super(type);
		this.mappedType = mappedType;
		this.mappedName = mappedName;
		this.mapping = mapping;
	}

	override public function clone():Event {
		return new MappingEvent(type, mappedType, mappedName, mapping);
	}
}
