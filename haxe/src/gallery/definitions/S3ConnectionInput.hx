package gallery.definitions;

typedef S3ConnectionInput = {
  var bucket:String;
  var region:String;
  var endpoint:String;
  var prefix:String;
  var accessKeyId:String;
  var secretAccessKey:String;
}
