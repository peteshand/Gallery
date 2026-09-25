//------------------------------------------------------------------------------
//  Copyright (c) 2009-2013 the original author or authors. All Rights Reserved.
//
//  NOTICE: You are permitted to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//------------------------------------------------------------------------------
package eva.ext.mediatorMap.impl;

import inject.utils.DescribedType;
import eva.ext.matching.ITypeMatcher;
import eva.ext.matching.TypeMatcher;
import eva.ext.mediatorMap.api.IMediatorMap;
import eva.ext.mediatorMap.dsl.IMediatorMapper;
import eva.ext.mediatorMap.dsl.IMediatorUnmapper;
import eva.ext.viewManager.api.IViewHandler;
import eva.IContext;

/**
 * @private
 */
class MediatorMap implements DescribedType implements IMediatorMap implements IViewHandler {
	/*============================================================================*/
	/* Private Properties                                                         */
	/*============================================================================*/
	private var _mappers:Map<String, Dynamic> = new Map<String, Dynamic>();

	private var _factory:MediatorFactory;

	private var _viewHandler:MediatorViewHandler;

	private var NULL_UNMAPPER = new NullMediatorUnmapper();

	/*============================================================================*/
	/* Constructor                                                                */
	/*============================================================================*/
	/**
	 * @private
	 */
	public function new(context:IContext) {
		_factory = new MediatorFactory(context.injector);
		_viewHandler = new MediatorViewHandler(_factory);
	}

	/*============================================================================*/
	/* Public Functions                                                           */
	/*============================================================================*/
	/**
	 * @inheritDoc
	 */
	public function mapMatcher(matcher:ITypeMatcher):IMediatorMapper {
		var descriptor:String = matcher.createTypeFilter().descriptor;
		var mediatorMapper:IMediatorMapper = _mappers.get(descriptor);
		if (mediatorMapper == null) {
			mediatorMapper = createMapper(matcher);
			_mappers.set(descriptor, mediatorMapper);
		}
		return mediatorMapper;
	}

	/**
	 * @inheritDoc
	 */
	public function map(type:Class<Dynamic>):IMediatorMapper {
		return mapMatcher(new TypeMatcher().allOf([type]));
	}

	/**
	 * @inheritDoc
	 */
	public function unmapMatcher(matcher:ITypeMatcher):IMediatorUnmapper {
		var descriptor:String = matcher.createTypeFilter().descriptor;
		var val = _mappers.get(descriptor);
		if (val != null)
			return val;
		else
			return NULL_UNMAPPER;
		// return _mappers[matcher.createTypeFilter().descriptor] || NULL_UNMAPPER;
	}

	/**
	 * @inheritDoc
	 */
	public function unmap(type:Class<Dynamic>):IMediatorUnmapper {
		return unmapMatcher(new TypeMatcher().allOf([type]));
	}

	/**
	 * @inheritDoc
	 */
	public function handleView(view:Dynamic, type:Class<Dynamic>):Void {
		_viewHandler.handleView(view, type);
	}

	/**
	 * @inheritDoc
	 */
	public function mediate(item:Dynamic):Void {
		_viewHandler.handleItem(item, Type.getClass(item));
	}

	/**
	 * @inheritDoc
	 */
	public function unmediate(item:Dynamic):Void {
		_factory.removeMediators(item);
	}

	/**
	 * @inheritDoc
	 */
	public function unmediateAll():Void {
		_factory.removeAllMediators();
	}

	/*============================================================================*/
	/* Private Functions                                                          */
	/*============================================================================*/
	private function createMapper(matcher:ITypeMatcher):IMediatorMapper {
		return new MediatorMapper(matcher.createTypeFilter(), _viewHandler);
	}
}
