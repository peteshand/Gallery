package gallery.view.library.collection;

class CollectionCardViewMediator extends Mediator {
  @inject public var view:CollectionCardView;
  @inject public var media:MediaModel;
  var observer:js.html.IntersectionObserver;

  override public function initialize():Void {
    media.paths.add(view.showImages).fireOnAdd();
    var images = view.element.querySelectorAll('[data-cover-id]');
    for (index in 0...images.length) {
      var image:ImageElement = cast images.item(index);
      image.addEventListener('load', function(_) image.classList.add('loaded'));
      image.addEventListener('error', function(_) image.classList.remove('loaded'));
      if (image.complete && image.naturalWidth > 0) image.classList.add('loaded');
    }
    observer = new js.html.IntersectionObserver(function(entries, _) {
      for (entry in entries) if (entry.isIntersecting) {
        for (asset in view.assets) if (asset.mediaUrl == '' && (asset.thumbnailUrl == null || asset.thumbnailUrl == ''))
          media.requested.dispatch({id:asset.id, variant:'thumbnail'});
        observer.disconnect();
        break;
      }
    }, {rootMargin:'240px'});
    observer.observe(view.element);
  }

  override public function destroy():Void {
    media.paths.remove(view.showImages);
    if (observer != null) observer.disconnect();
  }
}
