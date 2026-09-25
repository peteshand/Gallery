package gallery.definitions;

typedef S3ConnectionStatus = {
  var configured:Bool;
  var credentialsAvailable:Bool;
  var bucket:String;
  var region:String;
  var endpoint:String;
  var prefix:String;
  var maskedKeyId:String;
  var lastVerifiedAt:Null<Float>;
}
