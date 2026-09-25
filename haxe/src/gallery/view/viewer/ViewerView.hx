package gallery.view.viewer;


class ViewerView extends DomContainer {
  public var closeButton(default, null):Element;
  public var infoButton(default, null):Element;
  public var previousButton(default, null):Element;
  public var nextButton(default, null):Element;
  public var favoriteButton(default, null):Element;
  public var backupButton(default, null):Element;
  public var downloadButton(default, null):Element;
  public var stage(default, null):Element;
  var image:ImageElement;
  var previousImage:ImageElement;
  var nextImage:ImageElement;
  var imageTrack:Element;
  var title:Element;
  var details:Element;

  public function new() {
    super('viewer hidden', Browser.document.createElement('div'));
    id = 'viewer';
    element.setAttribute('role', 'dialog');
    element.setAttribute('aria-label', 'Photo viewer');
  }

  override public function initialize():Void {
    element.innerHTML = '<div class="viewer-header"><button id="viewer-close" class="viewer-icon" aria-label="Close">←</button><span id="viewer-title"></span><button id="viewer-info" class="viewer-icon" aria-label="Details">ⓘ</button></div>'
      + '<div class="viewer-stage"><button id="viewer-prev" class="viewer-arrow" aria-label="Previous photo">‹</button><div class="viewer-track"><img id="viewer-previous-image" alt=""><img id="viewer-image" alt="Selected photo"><img id="viewer-next-image" alt=""></div><button id="viewer-next" class="viewer-arrow" aria-label="Next photo">›</button></div>'
      + '<div id="viewer-details" class="viewer-details hidden"></div><div class="viewer-actions"><button id="viewer-favorite" aria-label="Favorite">♡</button></div>';
    closeButton = element.querySelector('#viewer-close');
    infoButton = element.querySelector('#viewer-info');
    previousButton = element.querySelector('#viewer-prev');
    nextButton = element.querySelector('#viewer-next');
    favoriteButton = element.querySelector('#viewer-favorite');
    stage = element.querySelector('.viewer-stage');
    image = cast element.querySelector('#viewer-image');
    previousImage = cast element.querySelector('#viewer-previous-image');
    nextImage = cast element.querySelector('#viewer-next-image');
    imageTrack = element.querySelector('.viewer-track');
    title = element.querySelector('#viewer-title');
    details = element.querySelector('#viewer-details');
  }

  public function showNeighbors(previousUrl:String, nextUrl:String):Void {
    if (previousUrl == '') previousImage.removeAttribute('src'); else previousImage.src = previousUrl;
    if (nextUrl == '') nextImage.removeAttribute('src'); else nextImage.src = nextUrl;
  }

  public function dragPhoto(dx:Float, dy:Float):Void {
    imageTrack.style.transition = 'none';
    element.style.transition = 'none';
    if (Math.abs(dx) > Math.abs(dy)) imageTrack.style.transform = 'translate3d(calc(-33.333333% + ' + dx + 'px),0,0)';
    else if (dy > 0) element.style.transform = 'translate3d(0,' + dy + 'px,0)';
  }

  public function settlePhoto(offset:Int):Void {
    imageTrack.style.transition = 'transform 180ms ease-out';
    imageTrack.style.transform = 'translate3d(' + (offset < 0 ? '0%' : offset > 0 ? '-66.666667%' : '-33.333333%') + ',0,0)';
  }

  public function dismissPhoto():Void {
    element.style.transition = 'transform 180ms ease-out';
    element.style.transform = 'translate3d(0,100%,0)';
  }

  public function resetPhotoMotion():Void {
    imageTrack.style.transition = 'none'; imageTrack.style.transform = 'translate3d(-33.333333%,0,0)';
    element.style.transition = 'none'; element.style.transform = '';
  }

  public function setAndroidInsets(enabled:Bool):Void {
    element.classList.toggle('viewer-android', enabled);
  }

  public function present(asset:Asset, detailOpen:Bool, canBackup:Bool, backedUp:Bool, busy:Bool, message:String, ?displayUrl:String, ?exportMessage:String):Void {
    element.classList.toggle('hidden', asset == null);
    if (asset == null) return;
    var url = displayUrl == null ? asset.mediaUrl : displayUrl;
    if (url == '') image.removeAttribute('src'); else image.src = url;
    image.alt = asset.filename;
    title.textContent = asset.filename;
    favoriteButton.textContent = asset.favorite ? '♥' : '♡';
    details.classList.toggle('hidden', !detailOpen);
    details.innerHTML = '';
    var lines = ['Taken: ' + asset.takenAt, 'Collection: ' + asset.collection, 'File: ' + asset.filename];
    if (asset.description != null && asset.description != '') lines.push('Description: ' + asset.description);
    if (asset.latitude != null && asset.longitude != null && (asset.latitude != 0 || asset.longitude != 0)) lines.push('Location: ' + asset.latitude + ', ' + asset.longitude);
    for (line in lines) { var row = create('p'); row.textContent = line; details.appendChild(row); }
    if (canBackup) {
      var heading = create('strong'); heading.textContent = 'Cloud backup'; details.appendChild(heading);
      var state = create('p');
      state.textContent = switch (asset.syncState) {
        case 'synced': 'Backed up' + (asset.syncedAt == null ? '' : ' · ' + asset.syncedAt);
        case 'preparing' | 'uploading': 'Backup in progress';
        case 'failed': 'Backup failed' + (asset.syncError == null ? '' : ': ' + asset.syncError);
        default: 'Not backed up';
      };
      details.appendChild(state);
      backupButton = create('button', 'secondary-button');
      backupButton.textContent = switch (asset.syncState) {
        case 'synced': 'Backed up';
        case 'failed': 'Retry backup';
        case 'preparing' | 'uploading': 'Backing up…';
        default: 'Back up now';
      };
      if (backedUp || busy || asset.syncState == 'preparing' || asset.syncState == 'uploading') backupButton.setAttribute('disabled', '');
      details.appendChild(backupButton);
      if (message != '') { var row = create('p'); row.textContent = message; details.appendChild(row); }
      downloadButton = create('button', 'secondary-button');
      downloadButton.textContent = 'Download original';
      details.appendChild(downloadButton);
      if (exportMessage != null && exportMessage != '') { var note = create('p'); note.textContent = exportMessage; details.appendChild(note); }
    }
  }

  function create(tag:String, ?className:String):Element {
    var result = Browser.document.createElement(tag);
    if (className != null) result.className = className;
    return result;
  }
}
