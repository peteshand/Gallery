package gallery.view.settings.source;

class SourceFoldersViewMediator extends Mediator {
  @inject public var view:SourceFoldersView;
  @inject public var gallery:GalleryModel;
  @inject public var library:LibraryModel;

  override public function initialize():Void {
    view.initialize();
    gallery.sourcePaths.add(function(_) present()).fireOnAdd();
    library.importProgress.add(function(_) present()).fireOnAdd();
    library.loading.add(function(_) present()).fireOnAdd();
    view.scanButton.addEventListener('click', function(_) gallery.importAllSourcesRequested.dispatch());
    view.element.addEventListener('click', function(event:MouseEvent) {
      var target:Element = cast event.target;
      if (target == null || !target.classList.contains('source-folder-remove')) return;
      var index = Std.parseInt(target.getAttribute('data-source-index'));
      if (index != null && index >= 0 && index < gallery.sourcePaths.value.length)
        gallery.removeSourceRequested.dispatch(gallery.sourcePaths.value[index]);
    });
  }

  function present():Void {
    var progress = library.importProgress.value;
    view.show(gallery.sourcePaths.value, library.loading.value || (progress != null && progress.running));
  }
}
