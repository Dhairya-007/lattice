/// Undo and redo for committed edits.
library;

/// One cell's value before and after an edit.
///
/// Changes are recorded per cell rather than per row so that undo works
/// whatever shape the row model has. An immutable model could be restored by
/// keeping the old row object, but a model whose setter mutates in place
/// cannot: the "old row" and the new one are the same object. Replaying a
/// value through the column's setter is the one move that works for both.
class CellEdit<T> {
  const CellEdit({
    required this.row,
    required this.field,
    required this.before,
    required this.after,
  });

  /// The row as it was when the change was made.
  ///
  /// Used to find the row again. A grid with a `rowKey` matches by identity,
  /// so this need not still be the instance the source holds; without one it
  /// has to be, which is why an immutable row model wants a key.
  final T row;

  final String field;

  /// The value the cell held before the edit, and after it.
  final Object? before;
  final Object? after;

  /// This change, the other way round.
  CellEdit<T> get inverse =>
      CellEdit<T>(row: row, field: field, before: after, after: before);

  @override
  String toString() => 'CellEdit($field: $before -> $after)';
}

/// One step of undo: everything a single user action changed.
///
/// A paste over a range changes many cells and has to come back in one
/// keystroke, so the unit of history is the action and not the cell.
class EditAction<T> {
  const EditAction({required this.label, required this.changes});

  /// What the user did, for an "Undo paste" menu item.
  final String label;

  final List<CellEdit<T>> changes;

  bool get isEmpty => changes.isEmpty;

  /// The action that undoes this one.
  EditAction<T> get inverse => EditAction<T>(
        label: label,
        changes: [for (final change in changes.reversed) change.inverse],
      );

  @override
  String toString() => 'EditAction($label, ${changes.length} cells)';
}

/// A bounded undo/redo stack of [EditAction]s.
///
/// Bounded because the alternative is a grid that holds every row it has ever
/// edited: at a few hundred cells per paste, an unbounded history over a
/// session is a leak with a user-visible cause and no user-visible symptom.
class EditHistory<T> {
  EditHistory({this.limit = 50}) : assert(limit > 0, 'limit must be positive');

  /// How many actions are kept. The oldest is dropped past this.
  final int limit;

  final List<EditAction<T>> _undo = [];
  final List<EditAction<T>> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Labels of the actions that would be undone and redone next, for menu
  /// items. Null when there is nothing to undo or redo.
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  int get length => _undo.length;

  /// Records an action the user has just done, which clears the redo stack:
  /// once they edit again, the future they undid is no longer reachable.
  void record(EditAction<T> action) {
    if (action.isEmpty) return;
    _undo.add(action);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  /// Takes the next action to undo, moving it to the redo stack.
  EditAction<T>? takeUndo() {
    if (_undo.isEmpty) return null;
    final action = _undo.removeLast();
    _redo.add(action);
    return action;
  }

  /// Takes the next action to redo, moving it back to the undo stack.
  EditAction<T>? takeRedo() {
    if (_redo.isEmpty) return null;
    final action = _redo.removeLast();
    _undo.add(action);
    return action;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
