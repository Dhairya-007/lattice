/// A minimal listenable, so the engine stays free of any UI framework.
library;

/// Callback invoked when an observable object changes.
typedef GridListener = void Function();

/// The smallest useful observable: add a listener, get notified, dispose.
///
/// Flutter's `ChangeNotifier` would do the job, but depending on it would drag
/// the Flutter SDK into the engine and shut the door on the web adapters. The
/// Flutter package bridges this to `Listenable` in a few lines instead.
mixin GridChangeNotifier {
  final List<GridListener> _listeners = [];
  bool _disposed = false;
  int _muteDepth = 0;
  bool _dirtyWhileMuted = false;

  bool get hasListeners => _listeners.isNotEmpty;

  bool get isDisposed => _disposed;

  void addListener(GridListener listener) {
    _assertAlive();
    _listeners.add(listener);
  }

  void removeListener(GridListener listener) {
    _listeners.remove(listener);
  }

  /// Notifies listeners, unless a [batch] is in progress.
  void notifyListeners() {
    if (_disposed) return;
    if (_muteDepth > 0) {
      _dirtyWhileMuted = true;
      return;
    }
    // Iterate a copy: a listener may add or remove listeners while running.
    for (final listener in List<GridListener>.of(_listeners)) {
      listener();
    }
  }

  /// Runs [action], emitting at most one notification afterwards.
  ///
  /// Nested batches collapse into the outermost one, so composing operations
  /// that each notify never produces a storm of rebuilds.
  R batch<R>(R Function() action) {
    _muteDepth++;
    try {
      return action();
    } finally {
      _muteDepth--;
      if (_muteDepth == 0 && _dirtyWhileMuted) {
        _dirtyWhileMuted = false;
        notifyListeners();
      }
    }
  }

  void dispose() {
    _listeners.clear();
    _disposed = true;
  }

  void _assertAlive() {
    if (_disposed) {
      throw StateError('$runtimeType was used after being disposed.');
    }
  }
}
