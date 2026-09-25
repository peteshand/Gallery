//------------------------------------------------------------------------------
//  Copyright (c) 2009-2013 the original author or authors. All Rights Reserved.
//
//  NOTICE: You are permitted to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//------------------------------------------------------------------------------
package eva.ext.contextView;

import inject.utils.DescribedType;
import eva.ext.viewManager.api.IViewManager;
import eva.IConfig;

/**
 * This configuration file adds the ContextView to the viewManager.
 *
 * It requires that the ViewManagerExtension, ContextViewExtension
 * and a ContextView have been installed.
 */
class ContextViewListenerConfig implements DescribedType implements IConfig {
	/*============================================================================*/
	/* Public Properties                                                          */
	/*============================================================================*/
	@inject public var contextView:ContextView;

	@inject public var viewManager:IViewManager;

	@:keep public function new() {}

	/*============================================================================*/
	/* Public Functions                                                           */
	/*============================================================================*/
	/**
	 * @inheritDoc
	 */
	public function configure():Void {
		// Adds the Context View to the View Manager at startup
		viewManager.addContainer(contextView.view);
	}
}
