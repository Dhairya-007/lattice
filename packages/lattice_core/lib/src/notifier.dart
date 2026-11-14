/// A minimal listenable, so the engine stays free of any UI framework.
library;

/// Callback invoked when an observable object changes.
typedef GridListener = void Function();

/// Callback invoked with what changed.
typedef GridChangeListener = void Function(Set<GridChange> changes);

/// What changed, so a listener can repaint only what depends on it.
///
/// A bare "something changed" forces an adapter to rebuild everything: click
/// one cell and every visible row and cell is rebuilt, because the adapter
/// has no way to tell a selection change from a new set of rows. On a large
/// grid that is the single biggest avoidable cost, and only the engine knows
/// which it was.
enum GridChange {
  /// The rows themselves: a new result, a different order, a different page,
  /// a group opened, a value written.
  rows,

  /// Column geometry: widths, order, pinning, visibility, stacked headers.
  layout,

  /// Selection, the active cell or the range.
  selection,

  /// The edit session: opened, retyped, committed or cancelled.
  edit,

  /// Chrome around the rows: loading, a fetch error, a pending write.
  status,
}

/// Every kind of change, which is what a caller that does not say means.
const Set<GridChange> everyGridChange = {
  GridChange.rows,
  GridChange.layout,
  GridChange.selection,
  GridChange.edit,
  GridChange.status,
};

/// The smallest useful observable: add a listener, get notified, dispose.
///
/// Flutter's `ChangeNotifier` would do the job, but depending on it would drag
/// the Flutter SDK into the engine and shut the door on the web adapters. The
/// Flutter package bridges this to `Listenable` in a few lines instead.
mixin GridChangeNotifier {
  final List<GridListener> _listeners = [];
  final List<GridChangeListener> _changeListeners = [];
  bool _disposed = false;
  int _muteDepth = 0;
  bool _dirtyWhileMuted = false;
  Set<GridChange> _mutedChanges = <GridChange>{};
  Set<GridChange> _lastChanges = everyGridChange;

  bool get hasListeners => _listeners.isNotEmpty || _changeListeners.isNotEmpty;

  bool get isDisposed => _disposed;

  /// What the most recent notification was about.
  ///
  /// For a listener registered with [addListener], which is not given the set
  /// but can read it during the callback.
  Set<GridChange> get lastChanges => _lastChanges;

  void addListener(GridListener listener) {
    _assertAlive();
    _listeners.add(listener);
  }

  void removeListener(GridListener listener) {
    _listeners.remove(listener);
  }

  /// Registers a listener that is told what changed.
  ///
  /// Repaint what depends on the set and leave the rest alone: a
  /// [GridChange.selection] notification means no row's content has changed.
  void addChangeListener(GridChangeListener listener) {
    _assertAlive();
    _changeListeners.add(listener);
  }

  void removeChangeListener(GridChangeListener listener) {
    _changeListeners.remove(listener);
  }

  /// Notifies listeners, unless a [batch] is in progress.
  ///
  /// [changes] says what happened. Omitting it means everything may have
  /// changed, which is always safe and never informative; the engine passes
  /// a specific set, and so should a source that knows.
  void notifyListeners({Set<GridChange>? changes}) {
    if (_disposed) return;
    final what = changes == null || changes.isEmpty ? everyGridChange : changes;
    if (_muteDepth > 0) {
      _dirtyWhileMuted = true;
      // A batch notifies once for the union of what it did, so nothing a
      // listener needed to know about is dropped.
      _mutedChanges.addAll(what);
      return;
    }
    _lastChanges = what;
    // Iterate a copy: a listener may add or remove listeners while running.
    for (final listener in List<GridListener>.of(_listeners)) {
      listener();
    }
    for (final listener in List<GridChangeListener>.of(_changeListeners)) {
      listener(what);
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
        final changes = _mutedChanges;
        _mutedChanges = <GridChange>{};
        notifyListeners(changes: changes);
      }
    }
  }

  void dispose() {
    _listeners.clear();
    _changeListeners.clear();
    _disposed = true;
  }

  void _assertAlive() {
    if (_disposed) {
      throw StateError('$runtimeType was used after being disposed.');
    }
  }
}
