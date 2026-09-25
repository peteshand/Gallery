package gallery.definitions;

typedef Asset = {
  var id:String;
  var filename:String;
  var takenAt:String;
  var collection:String;
  var favorite:Bool;
  var mediaUrl:String;
  var ?thumbnailUrl:String;
  var description:Null<String>;
  var latitude:Null<Float>;
  var longitude:Null<Float>;
  var altitude:Null<Float>;
  var ?syncState:String;
  var ?syncedAt:Null<String>;
  var ?syncError:Null<String>;
}
