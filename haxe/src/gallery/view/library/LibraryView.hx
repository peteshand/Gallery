package gallery.view.library;


class LibraryView extends DomContainer {
  public var importButton(default, null):Element;
  public var searchInput(default, null):InputElement;
  var tiles:Array<ThumbnailView> = [];
  var cards:Array<CollectionCardView> = [];
  var stories:StoryCarouselView;
  var pending:Array<Asset> = [];
  var nextIndex = 0;
  var fixedGrid:Element;
  var sentinel:Element;
  var pageObserver:js.html.IntersectionObserver;
  var searchAssets:Array<Asset> = [];
  static inline var PAGE_SIZE = 160;

  public function new() {
    super('content', Browser.document.createElement('main'));
    id = 'content';
  }

  public function showGridDensity(density:Int):Void {
    element.classList.remove('grid-density-0', 'grid-density-1', 'grid-density-2');
    element.classList.add('grid-density-' + density);
  }

  public function present(tab:String, assets:Array<Asset>, collection:String, query:String, loading:Bool, cloudOnly:Bool):Void {
    clearPaging();
    for (tile in tiles) removeChild(tile);
    for (card in cards) removeChild(card);
    if (stories != null) { removeChild(stories); stories = null; }
    tiles = [];
    cards = [];
    element.innerHTML = '';
    importButton = null;
    searchInput = null;
    searchAssets = [];
    switch (tab) {
      case 'Photos': photos(assets, loading, cloudOnly);
      case 'Collections': collections(assets, collection);
      case 'Search': search(assets, query);
      default:
    }
  }

  function photos(assets:Array<Asset>, loading:Bool, cloudOnly:Bool):Void {
    var feed = assets.filter(function(asset) return !StringTools.startsWith(asset.collection, 'On this phone / ')
      || asset.collection == 'On this phone / Camera');
    if (feed.length == 0) {
      var empty = create('div', 'empty-state');
      var symbol = create('div', 'empty-symbol'); symbol.textContent = '▧'; empty.appendChild(symbol);
      var heading = create('h1'); heading.textContent = 'Your photos, all in one place'; empty.appendChild(heading);
      var help = create('p'); help.textContent = assets.length > 0 ? 'Your other device folders are in Collections.'
        : cloudOnly ? 'Connect cloud storage in Settings to see your backed-up photos.' : 'Import a photo folder to start your library.'; empty.appendChild(help);
      importButton = create('button', 'primary-button'); importButton.textContent = assets.length > 0 ? 'View collections'
        : cloudOnly ? 'Open settings' : 'Import photos';
      if (loading) importButton.setAttribute('disabled', '');
      empty.appendChild(importButton);
      element.appendChild(empty);
      return;
    }
    stories = new StoryCarouselView(feed);
    addChild(stories);
    element.appendChild(stories.element);
    var grid = create('div', 'photo-grid');
    element.appendChild(grid);
    beginPaging(feed, grid);
  }

  function collections(assets:Array<Asset>, collection:String):Void {
    if (collection == 'On this phone') {
      var back = create('button', 'back-button'); back.textContent = '← Collections'; back.setAttribute('data-collection-back', 'true'); element.appendChild(back);
      var heading = create('h1', 'page-title'); heading.textContent = 'On this phone'; element.appendChild(heading);
      var folders = new Map<String, Array<Asset>>();
      for (asset in assets) if (StringTools.startsWith(asset.collection, 'On this phone / ')) {
        if (!folders.exists(asset.collection)) folders.set(asset.collection, []);
        folders.get(asset.collection).push(asset);
      }
      var names = [for (name in folders.keys()) name];
      names.sort(function(a, b) {
        if (a == 'On this phone / Camera') return -1;
        if (b == 'On this phone / Camera') return 1;
        return Reflect.compare(a, b);
      });
      var list = create('div', 'collection-list'); element.appendChild(list);
      for (name in names) addCollectionCard(list, name, name.substr('On this phone / '.length), folders.get(name));
      return;
    }
    if (collection != null) {
      var back = create('button', 'back-button'); back.textContent = '← Collections'; back.setAttribute('data-collection-back', 'true'); element.appendChild(back);
      var heading = create('h1', 'page-title'); heading.textContent = collection; element.appendChild(heading);
      var grid = create('div', 'photo-grid'); element.appendChild(grid);
      beginPaging(assets.filter(function(asset) return collection == 'Favourites' ? asset.favorite : asset.collection == collection), grid);
      return;
    }
    var heading = create('h1', 'page-title'); heading.textContent = 'Collections'; element.appendChild(heading);
    var list = create('div', 'collection-list'); element.appendChild(list);
    addCollectionCard(list, 'Favourites', 'Favourites', assets.filter(function(asset) return asset.favorite));
    var phone = assets.filter(function(asset) return StringTools.startsWith(asset.collection, 'On this phone / '));
    if (phone.length > 0) addCollectionCard(list, 'On this phone', 'On this phone', phone);
    var names = new Map<String, Array<Asset>>();
    for (asset in assets) {
      if (StringTools.startsWith(asset.collection, 'On this phone / ')) continue;
      if (!names.exists(asset.collection)) names.set(asset.collection, []);
      names.get(asset.collection).push(asset);
    }
    var ordered = [for (name in names.keys()) name];
    ordered.sort(Reflect.compare);
    for (name in ordered) addCollectionCard(list, name, name, names.get(name));
  }

  function addCollectionCard(list:Element, key:String, label:String, assets:Array<Asset>):Void {
    var card = new CollectionCardView(label, assets);
    card.element.setAttribute('data-collection', key);
    cards.push(card);
    addChild(card);
    list.appendChild(card.element);
  }

  function search(assets:Array<Asset>, query:String):Void {
    var wrap = create('div', 'search-wrap');
    searchInput = cast create('input', 'search-input');
    searchInput.placeholder = 'Search filename, date or collection';
    searchInput.value = query;
    wrap.appendChild(searchInput); element.appendChild(wrap);
    var results = create('div', 'photo-grid'); element.appendChild(results);
    searchAssets = assets;
    filterSearch(query);
  }

  public function filterSearch(query:String):Void {
    clearPaging();
    for (tile in tiles) removeChild(tile);
    tiles = [];
    var results = element.querySelector('.photo-grid');
    if (results == null) return;
    results.innerHTML = '';
    var needle = query.toLowerCase();
    beginPaging(searchAssets.filter(function(asset) return needle == '' || asset.filename.toLowerCase().indexOf(needle) >= 0
      || asset.takenAt.indexOf(needle) >= 0 || asset.collection.toLowerCase().indexOf(needle) >= 0
      || (asset.description != null && asset.description.toLowerCase().indexOf(needle) >= 0)), results);
  }

  function clearPaging():Void {
    if (pageObserver != null) { pageObserver.disconnect(); pageObserver = null; }
    if (sentinel != null) { sentinel.remove(); sentinel = null; }
    pending = [];
    nextIndex = 0;
    fixedGrid = null;
  }

  function beginPaging(assets:Array<Asset>, grid:Element):Void {
    pending = assets;
    fixedGrid = grid;
    nextIndex = 0;
    appendPage();
    if (nextIndex >= pending.length) return;
    sentinel = create('div', 'page-sentinel');
    element.appendChild(sentinel);
    pageObserver = new js.html.IntersectionObserver(function(entries, _) {
      for (entry in entries) if (entry.isIntersecting) { appendPage(); break; }
    }, {rootMargin:'600px'});
    pageObserver.observe(sentinel);
  }

  function appendPage():Void {
    var end = Std.int(Math.min(nextIndex + PAGE_SIZE, pending.length));
    while (nextIndex < end) {
      var asset = pending[nextIndex++];
      addTile(fixedGrid, asset);
    }
    if (nextIndex >= pending.length && pageObserver != null) {
      pageObserver.disconnect(); pageObserver = null;
      sentinel.remove(); sentinel = null;
    }
  }

  function addTile(grid:Element, asset:Asset):Void {
    var tile = new ThumbnailView(asset);
    tiles.push(tile);
    addChild(tile);
    grid.appendChild(tile.element);
  }

  function create(tag:String, ?className:String):Element {
    var result = Browser.document.createElement(tag);
    if (className != null) result.className = className;
    return result;
  }
}
