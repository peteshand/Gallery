package eva.ext.modelMap.api;

import inject.mapping.InjectionMapping;

/**
 * @author P.J.Shand
 */
interface IModelMap {
	function map(type:Class<Dynamic>, key:String = null):InjectionMapping;
}
