package gallery.definitions;

typedef SyncStatus = {
  var running:Bool;
  var cancelling:Bool;
  var cancelled:Bool;
  var total:Int;
  var notSynced:Int;
  var preparing:Int;
  var uploading:Int;
  var synced:Int;
  var failed:Int;
  var currentName:Null<String>;
  var lastError:Null<String>;
}
