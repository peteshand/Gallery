package gallery.view.settings.menu;

class SettingsMenuView extends DomContainer {
  public function new() {
    super('settings-menu', Browser.document.createElement('nav'));
  }

  override public function initialize():Void {
    element.setAttribute('aria-label', 'Settings categories');
    element.innerHTML = '<button type="button" data-settings-page="photos"><span><strong>Photos</strong><small>Folders and photos on this device</small></span><span aria-hidden="true">›</span></button>'
      + '<button type="button" data-settings-page="cloud"><span><strong>Cloud storage</strong><small>S3 connection and credentials</small></span><span aria-hidden="true">›</span></button>'
      + '<button type="button" data-settings-page="backup" class="native-setting"><span><strong>Backup</strong><small>Upload status and controls</small></span><span aria-hidden="true">›</span></button>'
      + '<button type="button" data-settings-page="downloads" class="native-setting"><span><strong>Downloads and cache</strong><small>Cloud photos and device storage</small></span><span aria-hidden="true">›</span></button>'
      + '<button type="button" data-settings-page="about"><span><strong>About</strong><small>Gallery ' + BuildInfo.VERSION + '</small></span><span aria-hidden="true">›</span></button>';
  }

  public function showNative(enabled:Bool):Void {
    for (item in element.querySelectorAll('.native-setting')) (cast item:Element).classList.toggle('hidden', !enabled);
  }
}
