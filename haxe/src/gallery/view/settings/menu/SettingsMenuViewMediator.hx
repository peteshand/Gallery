package gallery.view.settings.menu;

class SettingsMenuViewMediator extends Mediator {
  @inject public var view:SettingsMenuView;
  @inject public var gallery:GalleryModel;
  @inject public var cloud:CloudModel;

  override public function initialize():Void {
    view.initialize();
    cloud.available.add(view.showNative).fireOnAdd();
    view.element.addEventListener('click', function(event:MouseEvent) {
      var target:Element = cast event.target;
      var button = target == null ? null : target.closest('[data-settings-page]');
      if (button != null) gallery.settingsPage.value = button.getAttribute('data-settings-page');
    });
  }
}
