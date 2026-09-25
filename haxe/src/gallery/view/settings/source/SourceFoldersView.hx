package gallery.view.settings.source;

class SourceFoldersView extends DomContainer {
  public var scanButton(default, null):Element;
  var list:Element;

  public function new() {
    super('source-folders', Browser.document.createElement('section'));
  }

  override public function initialize():Void {
    element.innerHTML = '<div class="source-folders-head"><h3>Photo folders</h3><button id="source-scan-all" class="secondary-button" type="button">Scan all folders</button></div>'
      + '<p>Each folder is scanned recursively. Adding a folder starts its first scan.</p>'
      + '<ul id="source-folders-list"></ul>'
      + '<p class="source-folders-note">Removing a folder stops future scans. Photos already in the library stay there.</p>';
    scanButton = element.querySelector('#source-scan-all');
    list = element.querySelector('#source-folders-list');
  }

  public function show(paths:Array<String>, running:Bool):Void {
    scanButton.toggleAttribute('disabled', running || paths.length == 0);
    list.innerHTML = '';
    if (paths.length == 0) {
      var empty = Browser.document.createElement('li');
      empty.className = 'source-folders-empty';
      empty.textContent = 'No folders added yet.';
      list.appendChild(empty);
      return;
    }
    for (index in 0...paths.length) {
      var row = Browser.document.createElement('li');
      row.className = 'source-folder';
      var path = Browser.document.createElement('span');
      path.textContent = paths[index];
      path.setAttribute('title', paths[index]);
      row.appendChild(path);
      var remove = Browser.document.createElement('button');
      remove.className = 'source-folder-remove secondary-button';
      remove.textContent = 'Remove';
      remove.setAttribute('type', 'button');
      remove.setAttribute('data-source-index', Std.string(index));
      remove.setAttribute('aria-label', 'Remove ' + paths[index] + ' from future scans');
      row.appendChild(remove);
      list.appendChild(row);
    }
  }
}
