/// Cell, row and range selection.
library;

/// What the user is allowed to select.
enum SelectionMode {
  none,
  singleRow,
  multiRow,
  singleCell,

  /// Rectangular cell ranges, as a spreadsheet does.
  cellRange,
}

/// Modifier keys in effect when a selection gesture happened.
///
/// The adapter translates platform keys into this, so the engine owns the
/// semantics - plain click replaces, ctrl/cmd toggles, shift extends - and
/// every adapter behaves the same way.
class SelectionModifiers {
  const SelectionModifiers({this.toggle = false, this.extend = false});

  static const SelectionModifiers none = SelectionModifiers();
  static const SelectionModifiers toggling = SelectionModifiers(toggle: true);
  static const SelectionModifiers extending = SelectionModifiers(extend: true);

  /// Ctrl on Windows and Linux, cmd on macOS.
  final bool toggle;

  /// Shift.
  final bool extend;
}

/// A single cell, addressed by row index and column field.
///
/// The field rather than a column index means a selection survives the user
/// reordering, hiding or resizing columns.
class CellAddress {
  const CellAddress(this.row, this.field);

  final int row;
  final String field;

  @override
  bool operator ==(Object other) =>
      other is CellAddress && other.row == row && other.field == field;

  @override
  int get hashCode => Object.hash(row, field);

  @override
  String toString() => 'CellAddress($row, $field)';
}

/// A rectangular block of cells between two anchors, inclusive.
class CellRange {
  const CellRange({
    required this.anchor,
    required this.focus,
    required this.fields,
  });

  /// Where the drag or shift-selection started.
  final CellAddress anchor;

  /// Where it currently ends.
  final CellAddress focus;

  /// Visible fields in display order, used to resolve which columns fall
  /// between the two anchors.
  final List<String> fields;

  int get firstRow => anchor.row <= focus.row ? anchor.row : focus.row;
  int get lastRow => anchor.row <= focus.row ? focus.row : anchor.row;

  int get _anchorColumn => fields.indexOf(anchor.field);
  int get _focusColumn => fields.indexOf(focus.field);

  int get firstColumn =>
      _anchorColumn <= _focusColumn ? _anchorColumn : _focusColumn;
  int get lastColumn =>
      _anchorColumn <= _focusColumn ? _focusColumn : _anchorColumn;

  int get rowCount => lastRow - firstRow + 1;
  int get columnCount => lastColumn - firstColumn + 1;

  /// Fields covered by this range, in display order.
  List<String> get coveredFields {
    if (firstColumn < 0) return const [];
    return fields.sublist(firstColumn, lastColumn + 1);
  }

  bool contains(CellAddress cell) {
    if (firstColumn < 0) return false;
    if (cell.row < firstRow || cell.row > lastRow) return false;
    final column = fields.indexOf(cell.field);
    // A field that is no longer on screen is in no range. Without the first
    // test, a range whose own anchor column had disappeared reported -1 as
    // its first column and then claimed to contain every missing field,
    // which disagreed with coveredFields - and a copy walked cells the range
    // said it did not cover.
    if (column < 0) return false;
    return column >= firstColumn && column <= lastColumn;
  }

  /// This range with both ends pulled inside [rowCount], or null when it has
  /// no rows left.
  CellRange? clampedTo(int rowCount) {
    if (rowCount <= 0) return null;
    if (lastRow < rowCount) return this;
    final last = rowCount - 1;
    return CellRange(
      anchor: CellAddress(
        anchor.row > last ? last : anchor.row,
        anchor.field,
      ),
      focus: CellAddress(focus.row > last ? last : focus.row, focus.field),
      fields: fields,
    );
  }

  /// Every cell in the range, row-major - the order a clipboard copy needs.
  Iterable<CellAddress> get cells sync* {
    for (var row = firstRow; row <= lastRow; row++) {
      for (final field in coveredFields) {
        yield CellAddress(row, field);
      }
    }
  }

  @override
  String toString() =>
      'CellRange($firstRow..$lastRow x ${coveredFields.join(',')})';
}

/// How much of the grid is selected, for a select-all control.
///
/// A checkbox needs three states, not two: "some" is what stops the header
/// checkbox lying about a partial selection.
enum SelectionCoverage { none, some, all }

/// Holds and mutates the current selection.
///
/// "Everything is selected" is held as a flag with a set of exceptions rather
/// than as a set of every index. Select-all over a million rows built a
/// million-entry set - 109ms, and then an entry to remap per row on every
/// re-sort - to express one bit of information. Inverted, select-all, the
/// coverage a header checkbox reads, and every membership test are O(1).
class SelectionState {
  SelectionState({this.mode = SelectionMode.multiRow});

  SelectionMode mode;

  /// Selected indices, or - when [_inverted] - the ones left out.
  final Set<int> _rows = <int>{};

  /// Whether [_rows] lists what is *not* selected.
  bool _inverted = false;

  /// How many rows "everything" covered when it was selected.
  int _invertedCount = 0;

  CellAddress? _activeCell;
  CellAddress? _anchor;
  CellRange? _range;

  List<int>? _sortedCache;

  /// Selected row indices, in ascending order.
  ///
  /// Materialised on demand and cached until the selection changes: it used
  /// to sort a fresh copy on every read, which an adapter does once per
  /// frame. Reading it over an inverted selection costs one entry per row, so
  /// prefer [isRowSelected] and [rowCount] where they will do.
  List<int> get selectedRows => _sortedCache ??= _materialise();

  List<int> _materialise() {
    if (!_inverted) return _rows.toList()..sort();
    return [
      for (var i = 0; i < _invertedCount; i++)
        if (!_rows.contains(i)) i,
    ];
  }

  /// Whether everything is selected, held as a flag rather than as a set.
  bool get isEverythingSelected => _inverted && _rows.isEmpty;

  /// The row indices whose identity has to be followed across a rebuild.
  ///
  /// The selected rows for an ordinary selection, and the *exceptions* for an
  /// inverted one - everything else stays selected whatever moves where, so
  /// a select-all over a million rows has nothing to follow.
  Iterable<int> get followedRows => _rows;

  /// Drops the cached list of indices.
  void _changed() => _sortedCache = null;

  Set<int> get rows => Set.unmodifiable(_inverted ? _materialise() : _rows);

  /// The focused cell, which keyboard navigation moves.
  CellAddress? get activeCell => _activeCell;

  /// The current rectangular range, when [SelectionMode.cellRange] is active.
  CellRange? get range => _range;

  /// Where the last shift-extendable gesture started.
  ///
  /// Row anchors carry an empty field, because a row click has no column.
  CellAddress? get anchor => _anchor;

  bool get isEmpty => rowCount == 0 && _activeCell == null;

  int get rowCount {
    if (!_inverted) return _rows.length;
    final count = _invertedCount - _rows.length;
    return count < 0 ? 0 : count;
  }

  bool isRowSelected(int index) {
    if (index < 0) return false;
    if (!_inverted) return _rows.contains(index);
    return index < _invertedCount && !_rows.contains(index);
  }

  /// Marks [index] selected or not, whichever way round the set is held.
  void _setSelected(int index, bool selected) {
    _changed();
    if (_inverted == selected) {
      _rows.remove(index);
    } else {
      _rows.add(index);
    }
  }

  /// Replaces the selection with exactly [indices].
  void _replaceWith(Iterable<int> indices) {
    _changed();
    _inverted = false;
    _invertedCount = 0;
    _rows
      ..clear()
      ..addAll(indices);
  }

  bool isCellSelected(CellAddress cell) {
    if (_range != null && _range!.contains(cell)) return true;
    if (_activeCell == cell) return true;
    return isRowSelected(cell.row) &&
        (mode == SelectionMode.singleRow || mode == SelectionMode.multiRow);
  }

  /// Applies a row click.
  void selectRow(int index,
      [SelectionModifiers modifiers = SelectionModifiers.none]) {
    switch (mode) {
      case SelectionMode.none:
        return;
      case SelectionMode.singleRow:
      case SelectionMode.singleCell:
        _replaceWith([index]);
        _anchor = CellAddress(index, '');
      case SelectionMode.multiRow:
      case SelectionMode.cellRange:
        if (modifiers.extend && _anchor != null) {
          final from = _anchor!.row <= index ? _anchor!.row : index;
          final to = _anchor!.row <= index ? index : _anchor!.row;
          _replaceWith([for (var i = from; i <= to; i++) i]);
        } else if (modifiers.toggle) {
          _setSelected(index, !isRowSelected(index));
          _anchor = CellAddress(index, '');
        } else {
          _replaceWith([index]);
          _anchor = CellAddress(index, '');
        }
    }
  }

  /// Applies a cell click, updating both the active cell and any range.
  void selectCell(
    CellAddress cell,
    List<String> fields, [
    SelectionModifiers modifiers = SelectionModifiers.none,
  ]) {
    if (mode == SelectionMode.none) return;
    _activeCell = cell;
    if (mode == SelectionMode.cellRange) {
      if (modifiers.extend && _anchor != null) {
        _range = CellRange(anchor: _anchor!, focus: cell, fields: fields);
        return;
      }
      _anchor = cell;
      _range = CellRange(anchor: cell, focus: cell, fields: fields);
      return;
    }
    _anchor = cell;
    _range = null;
    if (mode == SelectionMode.singleRow || mode == SelectionMode.multiRow) {
      selectRow(cell.row, modifiers);
    }
  }

  /// Extends the range to [cell] without moving the anchor - a drag, or a
  /// shift-arrow key.
  void extendTo(CellAddress cell, List<String> fields) {
    if (mode != SelectionMode.cellRange || _anchor == null) {
      selectCell(cell, fields);
      return;
    }
    _activeCell = cell;
    _range = CellRange(anchor: _anchor!, focus: cell, fields: fields);
  }

  /// How much of [rowCount] rows is selected.
  SelectionCoverage coverageOf(int rowCount) {
    if (rowCount == 0) return SelectionCoverage.none;
    if (_inverted) {
      // Exceptions outside the current row count are not holes in it.
      var holes = 0;
      for (final index in _rows) {
        if (index >= 0 && index < rowCount) holes++;
      }
      if (holes == 0) return SelectionCoverage.all;
      return holes >= rowCount
          ? SelectionCoverage.none
          : SelectionCoverage.some;
    }
    if (_rows.isEmpty) return SelectionCoverage.none;
    // Count only rows that still exist: a stale index must not make a
    // partial selection look complete.
    var inRange = 0;
    for (final index in _rows) {
      if (index >= 0 && index < rowCount) inRange++;
    }
    if (inRange == 0) return SelectionCoverage.none;
    return inRange >= rowCount ? SelectionCoverage.all : SelectionCoverage.some;
  }

  /// Selects every one of [rowCount] rows, in constant time.
  void selectAll(int rowCount) {
    if (mode != SelectionMode.multiRow && mode != SelectionMode.cellRange) {
      return;
    }
    _changed();
    _inverted = true;
    _invertedCount = rowCount < 0 ? 0 : rowCount;
    _rows.clear();
  }

  void clear() {
    _changed();
    _inverted = false;
    _invertedCount = 0;
    _rows.clear();
    _activeCell = null;
    _anchor = null;
    _range = null;
  }

  /// Rewrites every row index through [moved], dropping the ones it maps to
  /// null or outside [rowCount].
  ///
  /// A selection is stored as indices because that is what an adapter renders,
  /// which means it otherwise follows the screen position rather than the row:
  /// select a row, sort, and the selection is on whatever now sits there.
  /// Given a way to recognise a row - see `GridController.rowKey` - the
  /// controller calls this after every rebuild so the selection follows the
  /// rows instead.
  ///
  /// A range is remapped by its two ends. After a reorder the cells between
  /// them are not the cells that were between them before; following the
  /// anchor and the focus is the only rule that keeps a rectangle a rectangle.
  void remapRows(int? Function(int index) moved, {required int rowCount}) {
    _changed();
    if (_inverted) {
      // Everything stays selected whatever moved where; only the holes have
      // to follow their rows. This is the point of holding it inverted: a
      // select-all over a million rows remaps nothing at all.
      final holes = <int>{};
      for (final index in _rows) {
        final next = moved(index);
        if (next != null && next >= 0 && next < rowCount) holes.add(next);
      }
      _rows
        ..clear()
        ..addAll(holes);
      _invertedCount = rowCount;
    } else {
      final rows = <int>{};
      for (final index in _rows) {
        final next = moved(index);
        if (next != null && next >= 0 && next < rowCount) rows.add(next);
      }
      _rows
        ..clear()
        ..addAll(rows);
    }

    CellAddress? remap(CellAddress? cell) {
      if (cell == null) return null;
      final next = moved(cell.row);
      if (next == null || next < 0 || next >= rowCount) return null;
      return next == cell.row ? cell : CellAddress(next, cell.field);
    }

    _activeCell = remap(_activeCell);
    _anchor = remap(_anchor);
    final range = _range;
    if (range != null) {
      final anchor = remap(range.anchor);
      final focus = remap(range.focus);
      _range = anchor == null || focus == null
          ? null
          : CellRange(anchor: anchor, focus: focus, fields: range.fields);
    }
  }

  /// Keeps the selection meaningful after the row count changes, dropping
  /// indices that no longer exist.
  ///
  /// Every part of the selection is clamped, not only the active cell: a
  /// range over rows 0..5 of a grid that now has two rows went on reporting
  /// `lastRow` 5, and a copy of it emitted rows that are not there.
  void clampTo(int rowCount) {
    _changed();
    _rows.removeWhere((i) => i >= rowCount);
    if (_inverted && rowCount < _invertedCount) _invertedCount = rowCount;
    if (rowCount <= 0) {
      _activeCell = null;
      _anchor = null;
      _range = null;
      return;
    }
    final last = rowCount - 1;
    final active = _activeCell;
    if (active != null && active.row > last) {
      _activeCell = CellAddress(last, active.field);
    }
    final anchor = _anchor;
    if (anchor != null && anchor.row > last) {
      _anchor = CellAddress(last, anchor.field);
    }
    _range = _range?.clampedTo(rowCount);
  }
}
