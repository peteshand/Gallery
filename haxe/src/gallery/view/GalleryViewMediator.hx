package gallery.view;


class GalleryViewMediator extends Mediator {
  @inject public var view:GalleryView;
  @inject public var mediatorMap:IMediatorMap;
  @inject public var gallery:GalleryModel;
  @inject public var library:LibraryModel;

  override public function initialize():Void {
    mediatorMap.map(LibraryView).toMediator(LibraryViewMediator);
    mediatorMap.map(SelectionBarView).toMediator(SelectionBarViewMediator);
    mediatorMap.map(ViewerView).toMediator(ViewerViewMediator);
    mediatorMap.map(SettingsView).toMediator(SettingsViewMediator);
    view.initialize();
    view.importButton.addEventListener('click', function(_) library.importRequested.dispatch(gallery.sourcePath.value));
    view.settingsButton.addEventListener('click', function(_) gallery.settingsOpen.value = true);
    view.selectionCancel.addEventListener('click', function(_) gallery.selectedIds.value = []);
    view.element.querySelector('.bottom-nav').addEventListener('click', function(event:js.html.MouseEvent) {
      var target:Element = cast event.target;
      var button = target.closest('[data-tab]');
      if (button != null) { gallery.collection.value = null; gallery.tab.value = button.getAttribute('data-tab'); }
    });
    Browser.document.addEventListener('keydown', onKeyDown);
    library.loading.add(view.showLoading).fireOnAdd();
    library.status.add(function(_) showStatus());
    library.error.add(function(_) showStatus());
    gallery.selectedIds.add(function(ids) view.showSelection(ids.length)).fireOnAdd();
    gallery.cloudOnlyDevice.add(function(value) {
      view.importButton.classList.toggle('hidden', value);
      view.setAndroidInsets(value);
    }).fireOnAdd();
    gallery.tab.add(view.showTab).fireOnAdd();
    showStatus();
  }

  override public function destroy():Void Browser.document.removeEventListener('keydown', onKeyDown);

  function showStatus():Void {
    var error = library.error.value;
    view.showStatus(error != null ? error : library.status.value, error != null);
  }

  function onKeyDown(event:KeyboardEvent):Void {
    if (event.key == 'Escape' && gallery.selectedIds.value.length > 0) { gallery.selectedIds.value = []; return; }
    if (gallery.activePhotoId.value == null) return;
    switch (event.key) {
      case 'Escape': gallery.activePhotoId.value = null;
      case 'ArrowLeft': move(-1);
      case 'ArrowRight': move(1);
      default:
    }
  }

  function move(offset:Int):Void {
    var assets = library.assets.value;
    for (index in 0...assets.length) if (assets[index].id == gallery.activePhotoId.value) {
      var next = index + offset;
      if (next >= 0 && next < assets.length) gallery.activePhotoId.value = assets[next].id;
      return;
    }
  }
}
