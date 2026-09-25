package gallery.definitions;

typedef ImportResult = {
  var scanned:Int;
  var added:Int;
  var existing:Int;
  var errors:Array<String>;
}
