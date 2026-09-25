package gallery.view;


class GalleryView extends DomContainer {
  public var libraryView(default, null):LibraryView;
  public var viewerView(default, null):ViewerView;
  public var settingsView(default, null):SettingsView;
  public var selectionBarView(default, null):SelectionBarView;
  public var importButton(default, null):Element;
  public var settingsButton(default, null):Element;
  public var selectionCancel(default, null):Element;
  var status:Element;

  public function new() {
    super(null, Browser.document.getElementById('app'));
    id = 'app';
  }

  override public function initialize():Void {
    element.innerHTML = '<div class="shell">'
      + '<header class="topbar"><div class="brand"><span class="brand-icon">✿</span><span>Gallery</span></div>'
      + '<div class="top-actions"><button id="import-button" class="icon-button" title="Import photos" aria-label="Import photos">＋</button>'
      + '<button id="settings-button" class="avatar-button" title="Settings" aria-label="Settings">G</button></div>'
      + '<div id="selection-header" class="selection-header hidden"><button id="selection-cancel" aria-label="Cancel selection">×</button><strong id="selection-count">0 selected</strong></div></header>'
      + '<div id="content-host"></div><div id="status" class="status" role="status"></div>'
      + '<nav class="bottom-nav" aria-label="Main navigation"><div class="nav-pill">'
      + '<button data-tab="Photos" class="nav-item active"><span class="nav-icon"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="m5 17 5-5 3 3 3-4 3 4"/></svg></span><span>Photos</span></button>'
      + '<button data-tab="Collections" class="nav-item"><span class="nav-icon"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h6"/></svg></span><span>Collections</span></button></div>'
      + '<button data-tab="Search" class="nav-item search-fab" aria-label="Search"><span class="nav-icon"><svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/></svg></span><span class="search-label">Search</span></button></nav>'
      + '<div id="selection-host"></div></div><div id="viewer-host"></div><div id="settings-host"></div>';
    importButton = element.querySelector('#import-button');
    settingsButton = element.querySelector('#settings-button');
    selectionCancel = element.querySelector('#selection-cancel');
    status = element.querySelector('#status');
    libraryView = new LibraryView(); addChild(libraryView); element.querySelector('#content-host').appendChild(libraryView.element);
    selectionBarView = new SelectionBarView(); addChild(selectionBarView); element.querySelector('#selection-host').appendChild(selectionBarView.element);
    viewerView = new ViewerView(); addChild(viewerView); element.querySelector('#viewer-host').appendChild(viewerView.element);
    settingsView = new SettingsView(); addChild(settingsView); element.querySelector('#settings-host').appendChild(settingsView.element);
  }

  public function setAndroidInsets(enabled:Bool):Void {
    element.classList.toggle('android-native', enabled);
  }

  public function showLoading(value:Bool):Void importButton.toggleAttribute('disabled', value);
  public function showStatus(message:String, error:Bool):Void {
    status.textContent = message;
    status.classList.toggle('error', error);
  }
  public function showSelection(count:Int):Void {
    element.querySelector('.shell').classList.toggle('selection-active', count > 0);
    element.querySelector('.brand').classList.toggle('hidden', count > 0);
    element.querySelector('.top-actions').classList.toggle('hidden', count > 0);
    element.querySelector('#selection-header').classList.toggle('hidden', count == 0);
    element.querySelector('#selection-count').textContent = count + ' selected';
    element.querySelector('.bottom-nav').classList.toggle('hidden', count > 0);
  }
  public function showTab(tab:String):Void {
    for (item in element.querySelectorAll('.nav-item')) {
      var button:Element = cast item;
      button.classList.toggle('active', button.getAttribute('data-tab') == tab);
    }
  }
}
