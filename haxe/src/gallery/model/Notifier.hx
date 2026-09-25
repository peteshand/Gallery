package gallery.model;


/** Observable state holder. Models expose these; logic and mediators change their values. */
class Notifier<T> {
  public var value(default, set):T;
  final changed:Signal1<T>;
  var lastListener:T->Void;

  public function new(?initial:T) {
    changed = new Signal1<T>();
    value = initial;
  }

  function set_value(next:T):T {
    if (value != next) {
      value = next;
      changed.dispatch(next);
    }
    return next;
  }

  public function add(listener:T->Void):Notifier<T> {
    changed.add(listener);
    lastListener = listener;
    return this;
  }

  public function remove(listener:T->Void):Void changed.remove(listener);
  public function fireOnAdd():Notifier<T> {
    if (lastListener != null) lastListener(value);
    return this;
  }
}
