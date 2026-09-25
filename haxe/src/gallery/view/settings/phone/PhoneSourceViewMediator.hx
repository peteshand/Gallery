package gallery.view.settings.phone;

class PhoneSourceViewMediator extends Mediator {
  @inject public var view:PhoneSourceView;
  @inject public var model:PhoneModel;

  override public function initialize():Void {
    view.initialize();
    model.supported.add(function(_) present()).fireOnAdd();
    model.status.add(function(_) present()).fireOnAdd();
    model.busy.add(function(_) present()).fireOnAdd();
    model.message.add(function(_) present()).fireOnAdd();
    model.preferences.add(function(_) present()).fireOnAdd();
    view.accessButton.addEventListener('click', function(_) model.accessRequested.dispatch());
    view.refreshButton.addEventListener('click', function(_) model.refreshRequested.dispatch());
    view.saveButton.addEventListener('click', function(_) model.preferencesRequested.dispatch(view.selectedPreferences()));
  }

  function present():Void view.present(model.supported.value, model.status.value, model.preferences.value, model.busy.value, model.message.value);
}
