package gallery.view.library.collection;

class CollectionCardView extends DomContainer {
  public var assets(default, null):Array<Asset>;

  public function new(name:String, assets:Array<Asset>) {
    super('collection-card', Browser.document.createElement('button'));
    this.assets = assets.length >= 4 ? assets.slice(0, 4) : assets.slice(0, 1);
    element.setAttribute('data-collection', name);
    element.setAttribute('type', 'button');
    var cover = Browser.document.createElement('span');
    cover.className = this.assets.length == 4 ? 'collection-cover collection-collage' : 'collection-cover';
    for (asset in this.assets) {
      var image = Browser.document.createImageElement();
      image.alt = '';
      image.setAttribute('data-cover-id', asset.id);
      image.setAttribute('loading', 'lazy');
      var url = asset.thumbnailUrl == null || asset.thumbnailUrl == '' ? asset.mediaUrl : asset.thumbnailUrl;
      if (url != '') image.src = url;
      cover.appendChild(image);
    }
    element.appendChild(cover);
    var title = Browser.document.createElement('strong'); title.textContent = name; element.appendChild(title);
    var count = Browser.document.createElement('span'); count.className = 'collection-count';
    count.textContent = assets.length + (assets.length == 1 ? ' photo' : ' photos'); element.appendChild(count);
  }

  public function showImages(paths:Map<String, String>):Void {
    for (asset in assets) {
      var url = paths.get(asset.id + ':thumbnail');
      if (url == null || url == '') continue;
      var images = element.querySelectorAll('[data-cover-id]');
      for (index in 0...images.length) {
        var image:ImageElement = cast images.item(index);
        if (image.getAttribute('data-cover-id') == asset.id && image.getAttribute('src') != url) image.src = url;
      }
    }
  }
}
