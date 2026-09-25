package gallery.view.library;


class StoryCarouselViewMediator extends Mediator {
  @inject public var view:StoryCarouselView;
  @inject public var gallery:GalleryModel;
  @inject public var media:MediaModel;

  override public function initialize():Void {
    view.element.addEventListener('click', onClick);
    media.paths.add(view.showImages).fireOnAdd();
    for (index in 0...Std.int(Math.min(5, view.assets.length))) {
      var asset = view.assets[index];
      if (asset.mediaUrl == '' && (asset.thumbnailUrl == null || asset.thumbnailUrl == ''))
        media.requested.dispatch({id:asset.id, variant:'thumbnail'});
    }
  }

  override public function destroy():Void {
    view.element.removeEventListener('click', onClick);
    media.paths.remove(view.showImages);
  }

  function onClick(event:MouseEvent):Void {
    var target:Element = cast event.target;
    var card = target.closest('[data-open-id]');
    if (card != null && gallery.selectedIds.value.length == 0) gallery.activePhotoId.value = card.getAttribute('data-open-id');
  }
}
