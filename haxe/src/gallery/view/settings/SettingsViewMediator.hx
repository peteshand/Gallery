package gallery.view.settings;


class SettingsViewMediator extends Mediator {
  @inject public var view:SettingsView;
  @inject public var gallery:GalleryModel;
  @inject public var library:LibraryModel;
  @inject public var cloud:CloudModel;
  @inject public var media:MediaModel;
  @inject public var mediatorMap:IMediatorMap;
  var editing = false;

  override public function initialize():Void {
    mediatorMap.map(BackupView).toMediator(BackupViewMediator);
    mediatorMap.map(SourceFoldersView).toMediator(SourceFoldersViewMediator);
    mediatorMap.map(PhoneSourceView).toMediator(PhoneSourceViewMediator);
    view.initialize();
    gallery.settingsOpen.add(function(open) {
      view.show(open);
      if (open && cloud.available.value) cloud.refreshRequested.dispatch();
      if (open) library.importErrorsRequested.dispatch();
    }).fireOnAdd();
    gallery.sourcePath.add(function(path) view.showSource(path)).fireOnAdd();
    library.importProgress.add(view.showImport).fireOnAdd();
    library.importErrors.add(view.showImportErrors).fireOnAdd();
    gallery.canChooseSource.add(view.showChoose).fireOnAdd();
    cloud.available.add(view.showNative).fireOnAdd();
    media.thumbnailOnly.add(function(enabled) view.thumbnailOnlyInput.checked = enabled).fireOnAdd();
    cloud.connection.add(function(_) presentConnection());
    cloud.busy.add(function(_) presentConnection());
    cloud.message.add(function(message) {
      view.showMessage(message);
      if (message.indexOf('connection check passed') >= 0) view.showVerified();
    }).fireOnAdd();
    cloud.cache.add(view.showCache).fireOnAdd();
    cloud.catalogBusy.add(function(busy) view.cloudRefresh.toggleAttribute('disabled', busy)).fireOnAdd();
    view.closeButton.addEventListener('click', function(_) gallery.settingsOpen.value = false);
    view.sourceChoose.addEventListener('click', function(_) gallery.chooseSourceRequested.dispatch());
    view.thumbnailOnlyInput.addEventListener("change", function(_) media.thumbnailOnly.value = view.thumbnailOnlyInput.checked);
    view.sourceCancel.addEventListener('click', function(_) library.cancelImportRequested.dispatch());
    view.cloudForm.addEventListener('submit', save);
    view.cloudRemove.addEventListener('click', function(_) cloud.removeRequested.dispatch());
    view.cloudTest.addEventListener('click', function(_) cloud.testRequested.dispatch());
    view.cloudRefresh.addEventListener('click', function(_) cloud.catalogRefreshRequested.dispatch());
    view.cacheSave.addEventListener('click', function(_) cloud.cacheLimitRequested.dispatch(view.cacheLimit()));
    view.cloudEdit.addEventListener('click', function(_) {
      editing = !editing;
      if (editing) {
        view.input('key').value = '';
        view.input('secret').value = '';
        cloud.message.value = 'Enter a new access key ID and secret to replace the saved credentials.';
      }
      presentConnection();
    });
  }

  function save(event:Event):Void {
    event.preventDefault();
    var connection = cloud.connection.value;
    if (connection != null && connection.configured && !editing) return;
    var input:S3ConnectionInput = {
      bucket:view.input('bucket').value,
      region:view.input('region').value,
      endpoint:view.input('endpoint').value,
      prefix:view.input('prefix').value,
      accessKeyId:view.input('key').value,
      secretAccessKey:view.input('secret').value
    };
    view.input('secret').value = '';
    editing = false;
    cloud.saveRequested.dispatch(input);
  }

  function presentConnection():Void {
    view.showConnection(cloud.connection.value, editing, cloud.busy.value);
    if (cloud.message.value.indexOf('connection check passed') >= 0) view.showVerified();
  }
}
