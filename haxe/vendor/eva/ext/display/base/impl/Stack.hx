package eva.ext.display.base.impl;

import haxe.Timer;
import inject.utils.DescribedType;
import eva.ext.display.base.api.ILayerInitializer;
import eva.ext.display.base.api.ILayers;
import eva.ext.display.base.api.IStack;
import eva.IInjector;
import eva.IContext;

class Stack implements DescribedType implements IStack {
	var _injector:IInjector;
	var context:IContext;
	var initializers:Array<ILayerInitializer> = [];

	@inject public var layers:ILayers;

	public static var layerCount:Int = 0;

	var preContextLayers:Array<LayerInfo> = [];
	var setupTimer:Timer;

	/*============================================================================*/
	/* Constructor                                                                */
	/*============================================================================*/
	public function new(context:IContext) {
		this.context = context;
		_injector = context.injector;

		#if away3d
		addInitializerType(eva.ext.display.stage3D.away3d.impl.Away3DInitializer);
		#end

		#if starling
		addInitializerType(eva.ext.display.stage3D.starling.impl.StarlingInitializer);
		#end

		#if fuse
		addInitializerType(eva.ext.display.stage3D.fuse.impl.FuseInitializer);
		#end

		#if threejs
		throw "The thressjs lib has been deprecated in favour of three.hx (https://github.com/tong/three.hx)"
		#end

		#if three.hx
		addInitializerType(eva.ext.display.webGL.threejs.impl.ThreeJsInitializer);
		#end
	}

	inline public function addInitializerType(type:Class<ILayerInitializer>) {
		_injector.map(type);
		var initializer:ILayerInitializer = _injector.getInstance(type);
		initializers.push(initializer);
	}

	public function addInitializer(initializer:ILayerInitializer) {
		initializers.push(initializer);
	}

	/*============================================================================*/
	/* Public Functions                                                           */
	/*============================================================================*/
	public function addLayer(LayerClass:Class<Dynamic>, id:String = ""):Void {
		addLayerAt(LayerClass, -1, id);
	}

	public function addLayerAt(LayerClass:Class<Dynamic>, index:Int, id:String = ""):Void {
		preContextLayers.push({LayerClass: LayerClass, index: index, id: id});
		layerCount++;

		if (setupTimer == null)
			setupTimer = Timer.delay(setupLayers, 1);
	}

	function setupLayers() {
		setupTimer = null;

		for (layerInfo in preContextLayers) {
			var initializer = getInitializer(layerInfo.LayerClass);
			if (initializer == null) {
				throw "Can't find initializer for class " + Type.getClassName(layerInfo.LayerClass);
			}

			initializer.addLayer(layerInfo.LayerClass, layerInfo.index, layerCount, layerInfo.id);
		}
		preContextLayers = [];
	}

	public function removeLayerAt(index:Int):Void {
		layers.removeLayerAt(index);
	}

	function getInitializer(layerClass:Class<Dynamic>):ILayerInitializer {
		for (initializer in initializers) {
			if (initializer.checkLayerType(layerClass)) {
				return initializer;
			}
		}
		return null;
	}
}

typedef LayerInfo = {
	LayerClass:Class<Dynamic>,
	index:Int,
	id:String
}
