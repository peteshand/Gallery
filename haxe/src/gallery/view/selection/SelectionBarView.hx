package gallery.view.selection;

class SelectionBarView extends DomContainer {
  public var backupButton(default, null):Element;

  public function new() {
    super('selection-bar hidden', Browser.document.createElement('div'));
    id = 'selection-bar';
    element.setAttribute('role', 'toolbar');
    element.setAttribute('aria-label', 'Selected photo actions');
  }

  override public function initialize():Void {
    element.innerHTML = '<button id="selection-backup" type="button"><span aria-hidden="true">☁↑</span><span>Back up now</span></button>';
    backupButton = element.querySelector('#selection-backup');
  }

  public function present(count:Int, pending:Int, enabled:Bool, busy:Bool):Void {
    element.classList.toggle('hidden', count == 0);
    backupButton.toggleAttribute('disabled', !enabled || busy || pending == 0);
    backupButton.querySelector('span:last-child').textContent = pending == 0 ? 'Already backed up' : 'Back up now';
    backupButton.setAttribute('title', enabled ? 'Back up selected photos' : 'Set up Cloud storage in Settings first');
  }
}
