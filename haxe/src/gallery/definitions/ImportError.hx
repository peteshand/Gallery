package gallery.definitions;

typedef ImportError = {
  var path:String;
  var error:String;
  var attempts:Int;
  var lastAttemptAt:String;
}
