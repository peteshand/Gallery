package gallery.view.settings;


class BackupView extends DomContainer {
  public var syncButton(default, null):Element;
  var progress:Element;

  public function new() {
    super('sync-panel', Browser.document.createElement('div'));
  }

  override public function initialize():Void {
    element.innerHTML = '<h3>Photo backup</h3>'
      + '<p>Backup uploads each untouched original, a JPEG preview up to 1920 pixels, an uncropped JPEG thumbnail with a 320-pixel short side, and photo metadata. Your source files stay untouched.</p>'
      + '<button id="sync-start" class="primary-button hidden" type="button">Sync now</button>'
      + '<p id="sync-progress" role="status">Checking photo backup…</p>';
    syncButton = element.querySelector('#sync-start');
    progress = element.querySelector('#sync-progress');
  }

  public function present(status:SyncStatus, configured:Bool, busy:Bool, checkingCloud:Bool):Void {
    if (status == null) return;
    syncButton.classList.toggle('hidden', !configured || status.total == 0);
    syncButton.toggleAttribute('disabled', busy || status.cancelling || checkingCloud);
    if (checkingCloud) { progress.textContent = 'Checking S3 for existing backups…'; return; }
    var message = status.synced + ' of ' + status.total + ' photos backed up';
    if (status.cancelling) message += ' · Stopping after the current upload…';
    else if (status.running) message += ' · Uploading' + (status.currentName == null ? '…' : ' ' + status.currentName);
    else if (status.cancelled) message += ' · Backup stopped';
    else if (status.total > 0 && status.synced < status.total) message += ' · ' + status.notSynced + ' not synced';
    if (status.failed > 0) message += ' · ' + status.failed + ' failed. ' + (status.lastError == null ? 'Press Sync now to retry.' : status.lastError);
    progress.textContent = message;
    syncButton.textContent = status.running ? (status.cancelling ? 'Stopping…' : 'Cancel sync') : status.failed > 0 ? 'Retry failed photos' : 'Sync now';
  }
}
