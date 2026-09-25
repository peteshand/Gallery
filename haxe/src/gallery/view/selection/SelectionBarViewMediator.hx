package gallery.view.selection;


class SelectionBarViewMediator extends Mediator {
  @inject public var view:SelectionBarView;
  @inject public var gallery:GalleryModel;
  @inject public var library:LibraryModel;
  @inject public var cloud:CloudModel;

  override public function initialize():Void {
    view.initialize();
    gallery.selectedIds.add(function(_) present());
    library.assets.add(function(_) present());
    cloud.connection.add(function(_) present());
    cloud.progress.add(function(_) present());
    cloud.busy.add(function(_) present());
    cloud.selectedSyncStarted.add(function() gallery.selectedIds.value = []);
    view.backupButton.addEventListener('click', function(_) {
      if (view.backupButton.hasAttribute('disabled')) return;
      cloud.syncSelectedRequested.dispatch(gallery.selectedIds.value.copy());
    });
    present();
  }

  function present():Void {
    var pending = 0;
    for (asset in library.assets.value) if (gallery.selectedIds.value.indexOf(asset.id) >= 0 && asset.syncState != 'synced') pending++;
    var connection = cloud.connection.value;
    var progress = cloud.progress.value;
    view.present(gallery.selectedIds.value.length, pending, connection != null && connection.configured,
      cloud.busy.value || (progress != null && progress.running));
  }
}
