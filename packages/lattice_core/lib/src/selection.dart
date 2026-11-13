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
    if (cell.row < firstRow || cell.row > lastRow) return false;
    final column = fields.indexOf(cell.field);
    return column >= firstColumn && column <= lastColumn;
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

/// Holds and mutates the current selection.
class SelectionState {
  SelectionState({this.mode = SelectionMode.multiRow});

  SelectionMode mode;

  final Set<int> _rows = <int>{};
  CellAddress? _activeCell;
  CellAddress? _anchor;
  CellRange? _range;

  /// Selected row indices, in ascending order.
  List<int> get selectedRows => _rows.toList()..sort();

  Set<int> get rows => Set.unmodifiable(_rows);

  /// The focused cell, which keyboard navigation moves.
  CellAddress? get activeCell => _activeCell;

  /// The current rectangular range, when [SelectionMode.cellRange] is active.
  CellRange? get range => _range;

  bool get isEmpty => _rows.isEmpty && _activeCell == null;

  int get rowCount => _rows.length;

  bool isRowSelected(int index) => _rows.contains(index);

  bool isCellSelected(CellAddress cell) {
    if (_range != null && _range!.contains(cell)) return true;
    if (_activeCell == cell) return true;
    return _rows.contains(cell.row) &&
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
        _rows
          ..clear()
          ..add(index);
        _anchor = CellAddress(index, '');
      case SelectionMode.multiRow:
      case SelectionMode.cellRange:
        if (modifiers.extend && _anchor != null) {
          final from = _anchor!.row <= index ? _anchor!.row : index;
          final to = _anchor!.row <= index ? index : _anchor!.row;
          _rows
            ..clear()
            ..addAll([for (var i = from; i <= to; i++) i]);
        } else if (modifiers.toggle) {
          if (!_rows.remove(index)) _rows.add(index);
          _anchor = CellAddress(index, '');
        } else {
          _rows
            ..clear()
            ..add(index);
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

  void selectAll(int rowCount) {
    if (mode == SelectionMode.multiRow || mode == SelectionMode.cellRange) {
      _rows
        ..clear()
        ..addAll([for (var i = 0; i < rowCount; i++) i]);
    }
  }

  void clear() {
    _rows.clear();
    _activeCell = null;
    _anchor = null;
    _range = null;
  }

  /// Keeps the selection meaningful after the row count changes, dropping
  /// indices that no longer exist.
  void clampTo(int rowCount) {
    _rows.removeWhere((i) => i >= rowCount);
    final active = _activeCell;
    if (active != null && active.row >= rowCount) {
      _activeCell =
          rowCount == 0 ? null : CellAddress(rowCount - 1, active.field);
      _range = null;
    }
  }
}
