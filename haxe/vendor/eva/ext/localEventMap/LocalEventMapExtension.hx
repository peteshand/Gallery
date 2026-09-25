//------------------------------------------------------------------------------
//  Copyright (c) 2009-2013 the original author or authors. All Rights Reserved.
//
//  NOTICE: You are permitted to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//------------------------------------------------------------------------------
package eva.ext.localEventMap;

import eva.ext.localEventMap.api.IEventMap;
import eva.ext.localEventMap.impl.EventMap;
import eva.IContext;
import eva.IExtension;

/**
 * An Event Map keeps track of listeners and provides the ability
 * to unregister all listeners with a single method call.
 */
@:keepSub
class LocalEventMapExtension implements IExtension {
	/*============================================================================*/
	/* Public Functions                                                           */
	/*============================================================================*/
	/**
	 * @inheritDoc
	 */
	public function extend(context:IContext):Void {
		context.injector.map(IEventMap).toType(EventMap);
	}
}
