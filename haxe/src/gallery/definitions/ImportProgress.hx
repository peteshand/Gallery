package gallery.definitions;

typedef ImportProgress = {
  var running:Bool;
  var cancelling:Bool;
  var processed:Int;
  var added:Int;
  var existing:Int;
  var errors:Int;
  var current:String;
}
