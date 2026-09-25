package gallery.view.settings;


class BackupViewMediator extends Mediator {
  @inject public var view:BackupView;
  @inject public var cloud:CloudModel;

  override public function initialize():Void {
    view.initialize();
    cloud.connection.add(function(_) present());
    cloud.progress.add(function(_) present());
    cloud.busy.add(function(_) present());
    view.syncButton.addEventListener('click', function(_) cloud.syncRequested.dispatch());
    present();
  }

  function present():Void {
    var connection = cloud.connection.value;
    view.present(cloud.progress.value, connection != null && connection.configured, cloud.busy.value);
  }
}
