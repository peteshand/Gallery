package gallery.view.settings.phone;

class PhoneSourceView extends DomContainer {
  public var accessButton(default, null):Element;
  public var refreshButton(default, null):Element;
  public var saveButton(default, null):Element;
  var state:Element;
  var message:Element;

  public function new() {
    super('phone-source hidden', Browser.document.createElement('section'));
  }

  override public function initialize():Void {
    element.innerHTML = '<h3>Photos on this phone</h3>'
      + '<p>Show camera-roll photos beside your cloud photos. Gallery only reads them; backup stays manual until you enable it.</p>'
      + '<p id="phone-source-state" role="status"></p>'
      + '<div class="phone-source-actions"><button id="phone-access" class="secondary-button" type="button">Allow photo access</button>'
      + '<button id="phone-refresh" class="secondary-button" type="button">Scan phone photos</button></div>'
      + '<div class="phone-backup-options"><label><input id="phone-auto-backup" type="checkbox"> Auto back up photos</label>'
      + '<label><input id="phone-wifi-only" type="checkbox"> Back up on Wi-Fi only</label>'
      + '<label><input id="phone-background-backup" type="checkbox"> Continue backup in background</label></div>'
      + '<p>Automatic backup requires access to all photos. Background jobs run when Android allows them.</p>'
      + '<button id="phone-backup-save" class="secondary-button" type="button">Save backup options</button>'
      + '<p id="phone-source-message" role="status"></p>';
    accessButton = element.querySelector('#phone-access');
    refreshButton = element.querySelector('#phone-refresh');
    saveButton = element.querySelector('#phone-backup-save');
    state = element.querySelector('#phone-source-state');
    message = element.querySelector('#phone-source-message');
  }

  public function present(supported:Bool, status:PhoneStatus, preferences:BackupPreferences, busy:Bool, note:String):Void {
    element.classList.toggle('hidden', !supported);
    if (!supported) return;
    var access = status == null ? 'none' : status.access;
    state.textContent = switch access {
      case 'full': 'All phone photos available · ' + status.count + ' found';
      case 'selected': 'Selected phone photos available · ' + status.count + ' found';
      case _: 'Photo access has not been granted.';
    }
    accessButton.textContent = access == 'selected' ? 'Change photo access' : 'Allow photo access';
    accessButton.classList.toggle('hidden', access == 'full');
    refreshButton.classList.toggle('hidden', access == 'none');
    accessButton.toggleAttribute('disabled', busy);
    refreshButton.toggleAttribute('disabled', busy);
    saveButton.toggleAttribute('disabled', busy || preferences == null);
    if (preferences != null && !element.contains(Browser.document.activeElement)) {
      (cast element.querySelector('#phone-auto-backup'):InputElement).checked = preferences.autoBackup;
      (cast element.querySelector('#phone-wifi-only'):InputElement).checked = preferences.wifiOnly;
      (cast element.querySelector('#phone-background-backup'):InputElement).checked = preferences.backgroundBackup;
    }
    message.textContent = note;
  }

  public function selectedPreferences():BackupPreferences return {
    autoBackup:(cast element.querySelector('#phone-auto-backup'):InputElement).checked,
    wifiOnly:(cast element.querySelector('#phone-wifi-only'):InputElement).checked,
    backgroundBackup:(cast element.querySelector('#phone-background-backup'):InputElement).checked
  };
}
