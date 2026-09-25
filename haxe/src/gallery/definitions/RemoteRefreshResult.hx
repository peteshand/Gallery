package gallery.definitions;

typedef RemoteRefreshResult = {
  var scanned:Int;
  var added:Int;
  var updated:Int;
  var unchanged:Int;
  var errors:Array<String>;
}
