package gallery.view.library;


class StoryCarouselView extends DomContainer {
  public var assets(default, null):Array<Asset>;

  public function new(assets:Array<Asset>) {
    super('story-carousel', Browser.document.createElement('section'));
    this.assets = assets;
    element.setAttribute('aria-label', 'Highlights');
    var track = Browser.document.createElement('div');
    track.className = 'story-track';
    element.appendChild(track);
    addCard(track, 'Highlights', assets[0].id, true);
    if (assets.length > 1) addCard(track, assets[Std.int(Math.min(4, assets.length - 1))].collection, assets[Std.int(Math.min(4, assets.length - 1))].id, false);
  }

  function addCard(track:Element, label:String, id:String, collage:Bool):Void {
    var button = Browser.document.createElement('button');
    button.className = 'story-card';
    button.setAttribute('data-open-id', id);
    button.setAttribute('aria-label', label);
    var media = Browser.document.createElement('div');
    media.className = collage ? 'story-media story-collage' : 'story-media story-cover';
    var count = collage ? Std.int(Math.min(4, assets.length)) : 1;
    for (index in 0...count) {
      var cell = Browser.document.createElement('span');
      cell.className = 'story-image';
      cell.setAttribute('data-story-asset-id', collage ? assets[index].id : id);
      media.appendChild(cell);
    }
    button.appendChild(media);
    var title = Browser.document.createElement('span');
    title.className = 'story-title';
    title.textContent = label;
    button.appendChild(title);
    track.appendChild(button);
  }

  public function showImages(paths:Map<String, String>):Void {
    for (asset in assets) {
      var url = asset.thumbnailUrl == null || asset.thumbnailUrl == '' ? asset.mediaUrl : asset.thumbnailUrl;
      if (url == '') url = paths.get(asset.id + ':thumbnail');
      if (url == null || url == '') continue;
      for (cell in element.querySelectorAll('[data-story-asset-id="' + asset.id + '"]')) {
        var image:Element = cast cell;
        image.style.backgroundImage = 'url("' + StringTools.replace(url, '"', '%22') + '")';
      }
    }
  }
}
