package gallery.view.settings;


class SettingsView extends DomContainer {
  public var closeButton(default, null):Element;
  public var backButton(default, null):Element;
  public var menuView(default, null):SettingsMenuView;
  public var sourceChoose(default, null):Element;
  public var sourceCancel(default, null):Element;
  public var cloudForm(default, null):Element;
  public var cloudSave(default, null):Element;
  public var cloudTest(default, null):Element;
  public var cloudEdit(default, null):Element;
  public var cloudRemove(default, null):Element;
  public var cloudRefresh(default, null):Element;
  public var cacheSave(default, null):Element;
  public var backupView(default, null):BackupView;
  public var phoneView(default, null):PhoneSourceView;
  public var sourceFoldersView(default, null):SourceFoldersView;
  public var thumbnailOnlyInput(default, null):InputElement;
  var sourceLabel:Element;
  var sourceErrors:Element;
  var cloudState:Element;
  var cloudMessage:Element;
  var nativeArea:Element;
  var browserArea:Element;

  public function new() {
    super('settings hidden', Browser.document.createElement('div'));
    id = 'settings';
    element.setAttribute('role', 'dialog');
    element.setAttribute("aria-modal", "true");
    element.setAttribute('aria-label', 'Settings');
  }

  override public function initialize():Void {
    element.innerHTML = '<div class="settings-card"><div class="settings-title"><button id="settings-back" class="settings-back hidden" type="button" aria-label="Back to settings categories">‹</button><div class="settings-heading"><h2 id="settings-page-title">Settings</h2><small id="app-version">Version ' + BuildInfo.VERSION + '</small></div><button id="settings-close" aria-label="Close settings">×</button></div>'
      + '<section id="desktop-sources"><div id="source-folders-host"></div><p id="source-path"></p><button id="source-choose" class="secondary-button" type="button">Add photo folder</button>'
      + '<button id="source-cancel" class="secondary-button hidden" type="button">Cancel import</button><p id="source-progress" role="status"></p>'
      + '<details id="source-errors" class="hidden"><summary>Import errors</summary><ul id="source-error-list"></ul></details>'
      + '<p>The source files are read only. The catalogue is stored separately.</p></section><div id="phone-source-host"></div>'
      + '<h3 id="cloud-heading">Cloud storage</h3><div id="cloud-native"><p id="cloud-state" role="status">Checking local connection…</p><form id="cloud-form" autocomplete="off">'
      + '<label for="cloud-bucket">Bucket</label><input id="cloud-bucket" required spellcheck="false" autocomplete="off" placeholder="my-gallery-bucket">'
      + '<label for="cloud-region">Region</label><input id="cloud-region" required spellcheck="false" autocomplete="off" placeholder="ap-southeast-2">'
      + '<label for="cloud-endpoint">Endpoint (optional)</label><input id="cloud-endpoint" type="url" spellcheck="false" autocomplete="off" placeholder="https://…">'
      + '<label for="cloud-prefix">Object prefix (optional)</label><input id="cloud-prefix" spellcheck="false" autocomplete="off" value="gallery/" placeholder="gallery/">'
      + '<label for="cloud-key">Access key ID</label><input id="cloud-key" required spellcheck="false" autocomplete="off">'
      + '<label for="cloud-secret">Secret access key</label><input id="cloud-secret" required type="password" autocomplete="off">'
      + '<p>Credentials are saved in this device’s protected store. Saving does not upload photos yet.</p>'
      + '<div class="cloud-buttons"><button id="cloud-save" class="primary-button" type="submit">Save connection</button><button id="cloud-test" class="secondary-button hidden" type="button">Test connection</button><button id="cloud-edit" class="secondary-button hidden" type="button">Replace credentials</button><button id="cloud-remove" class="secondary-button" type="button">Remove</button></div>'
      + '</form><p id="cloud-message" role="status"></p><div id="backup-host"></div></div><p id="cloud-browser" class="hidden">Cloud settings are available in the native app.</p></div>';
    var card = element.querySelector('.settings-card');
    var photosPage = makePage(card, 'photos');
    photosPage.appendChild(element.querySelector('#desktop-sources'));
    photosPage.appendChild(element.querySelector('#phone-source-host'));
    var cloudPage = makePage(card, 'cloud');
    cloudPage.appendChild(element.querySelector('#cloud-heading'));
    cloudPage.appendChild(element.querySelector('#cloud-native'));
    cloudPage.appendChild(element.querySelector('#cloud-browser'));
    var backupPage = makePage(card, 'backup');
    backupPage.appendChild(element.querySelector('#backup-host'));
    var downloadsPage = makePage(card, 'downloads');
    var aboutPage = makePage(card, 'about');
    aboutPage.innerHTML = '<h3>Gallery</h3><p>Version ' + BuildInfo.VERSION + '</p>';
    menuView = new SettingsMenuView();
    addChild(menuView);
    card.insertBefore(menuView.element, photosPage);
    var native = element.querySelector('#cloud-native');
    var cloudExtras = Browser.document.createElement('section');
    cloudExtras.className = 'cloud-extras';
    cloudExtras.innerHTML = '<h3>Cloud library</h3><p>Read the photo catalogue from S3 onto this device. Images download as you browse.</p>'
      + '<label class="setting-toggle" for="thumbnail-only"><input id="thumbnail-only" type="checkbox"><span><strong>Only download thumbnails</strong><small>Use smaller images when viewing cloud photos. Originals remain available on request.</small></span></label>'
      + '<button id="cloud-refresh" class="secondary-button" type="button">Refresh cloud photos</button>'
      + '<h3>Photo cache</h3><p id="cache-usage">Checking cache…</p>'
      + '<label for="cache-limit">Maximum cache size (GB)</label><input id="cache-limit" type="number" min="0.064" max="50" step="0.1" value="2">'
      + '<button id="cache-save" class="secondary-button" type="button">Save cache limit</button>';
    downloadsPage.appendChild(cloudExtras);
    closeButton = element.querySelector('#settings-close');
    backButton = element.querySelector('#settings-back');
    sourceChoose = element.querySelector('#source-choose');
    sourceCancel = element.querySelector('#source-cancel');
    sourceLabel = element.querySelector('#source-path');
    sourceErrors = element.querySelector('#source-errors');
    cloudForm = element.querySelector('#cloud-form');
    cloudSave = element.querySelector('#cloud-save');
    cloudTest = element.querySelector('#cloud-test');
    cloudEdit = element.querySelector('#cloud-edit');
    cloudRemove = element.querySelector('#cloud-remove');
    cloudRefresh = element.querySelector('#cloud-refresh');
    cacheSave = element.querySelector('#cache-save');
    thumbnailOnlyInput = cast element.querySelector('#thumbnail-only');
    cloudState = element.querySelector('#cloud-state');
    cloudMessage = element.querySelector('#cloud-message');
    nativeArea = element.querySelector('#cloud-native');
    browserArea = element.querySelector('#cloud-browser');
    backupView = new BackupView();
    addChild(backupView);
    element.querySelector('#backup-host').appendChild(backupView.element);
    sourceFoldersView = new SourceFoldersView();
    addChild(sourceFoldersView);
    element.querySelector('#source-folders-host').appendChild(sourceFoldersView.element);
    phoneView = new PhoneSourceView();
    addChild(phoneView);
    element.querySelector('#phone-source-host').appendChild(phoneView.element);
  }

  function makePage(card:Element, name:String):Element {
    var page = Browser.document.createElement('section');
    page.className = 'settings-page hidden';
    page.setAttribute('data-settings-page', name);
    card.appendChild(page);
    return page;
  }

  public function showPage(page:String):Void {
    var title = switch page {
      case 'photos': 'Photos';
      case 'cloud': 'Cloud storage';
      case 'backup': 'Backup';
      case 'downloads': 'Downloads and cache';
      case 'about': 'About';
      case _: 'Settings';
    };
    element.querySelector('#settings-page-title').textContent = title;
    backButton.classList.toggle('hidden', page == 'home');
    menuView.element.classList.toggle('hidden', page != 'home');
    for (node in element.querySelectorAll('.settings-page')) {
      var pane:Element = cast node;
      pane.classList.toggle('hidden', pane.getAttribute('data-settings-page') != page);
    }
    element.scrollTop = 0;
  }

  public function show(open:Bool):Void element.classList.toggle('hidden', !open);
  public function showNative(enabled:Bool):Void {
    nativeArea.classList.toggle('hidden', !enabled);
    browserArea.classList.toggle('hidden', enabled);
  }
  public function showChoose(enabled:Bool):Void {
    sourceChoose.classList.toggle("hidden", !enabled);
    element.querySelector("#desktop-sources").classList.toggle("hidden", !enabled);
  }
  public function showSource(path:String):Void sourceLabel.textContent = path == null ? 'Choose a folder to begin importing.' : '';
  public function showImportErrors(errors:Array<ImportError>):Void {
    sourceErrors.classList.toggle('hidden', errors.length == 0);
    sourceErrors.querySelector('summary').textContent = errors.length + ' recent import error' + (errors.length == 1 ? '' : 's');
    var list = sourceErrors.querySelector('ul');
    list.innerHTML = '';
    for (item in errors) {
      var row = Browser.document.createElement('li');
      row.textContent = item.path + ': ' + item.error + ' (' + item.attempts + ' attempt' + (item.attempts == 1 ? '' : 's') + ')';
      list.appendChild(row);
    }
  }
  public function showImport(progress:ImportProgress):Void {
    var running = progress != null && progress.running;
    sourceCancel.classList.toggle('hidden', !running || progress.processed == 0);
    sourceCancel.toggleAttribute('disabled', running && progress.cancelling);
    element.querySelector('#source-progress').textContent = running ? progress.processed + ' processed · ' + progress.added + ' new · ' + progress.current : '';
  }
  public function input(name:String):InputElement return cast element.querySelector('#cloud-' + name);

  public function showConnection(connection:S3ConnectionStatus, editing:Bool, busy:Bool):Void {
    if (connection == null) return;
    if (!editing) {
      input('bucket').value = connection.bucket;
      input('region').value = connection.region;
      input('endpoint').value = connection.endpoint;
      input('prefix').value = connection.configured || connection.prefix != '' ? connection.prefix : 'gallery/';
    }
    var saved = connection.credentialsAvailable;
    var displaySaved = saved && !editing;
    var key = input('key'); var secret = input('secret');
    key.readOnly = displaySaved; secret.readOnly = displaySaved;
    key.required = !displaySaved; secret.required = !displaySaved;
    if (displaySaved) { key.value = connection.maskedKeyId; secret.value = 'saved-in-protected-store'; }
    else if (!editing) { key.value = ''; secret.value = ''; }
    secret.setAttribute('aria-label', displaySaved ? 'Secret access key saved securely; value hidden' : 'Secret access key');
    cloudSave.classList.toggle('hidden', displaySaved);
    cloudTest.classList.toggle('hidden', !displaySaved || !connection.configured);
    cloudEdit.classList.toggle('hidden', !saved);
    cloudEdit.textContent = editing ? 'Cancel replacement' : 'Replace credentials';
    cloudState.textContent = connection.configured
      ? 'Saved locally for ' + connection.bucket + ' · key ' + connection.maskedKeyId + (connection.lastVerifiedAt == null ? ' · S3 access not tested' : ' · last verified ' + Date.fromTime(connection.lastVerifiedAt).toString())
      : saved ? 'Credentials found, but connection details are incomplete' : 'No S3 connection saved';
    cloudRemove.toggleAttribute('disabled', busy || !saved);
    for (button in [cloudSave, cloudTest, cloudEdit]) button.toggleAttribute('disabled', busy);
  }

  public function showMessage(message:String):Void cloudMessage.textContent = message;
  public function showVerified():Void cloudState.textContent = 'S3 access verified for this bucket and prefix just now';
  public function showCache(status:CacheStatus):Void {
    if (status == null) return;
    var gb = 1024.0 * 1024 * 1024;
    element.querySelector('#cache-usage').textContent = Math.round(status.usedBytes / gb * 100) / 100 + ' GB used for ' + status.itemCount + ' files';
    (cast element.querySelector('#cache-limit'):InputElement).value = Std.string(Math.round(status.limitBytes / gb * 100) / 100);
  }
  public function cacheLimit():Float return Std.parseFloat((cast element.querySelector('#cache-limit'):InputElement).value) * 1024 * 1024 * 1024;

}
