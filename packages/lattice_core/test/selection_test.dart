import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

void main() {
  const fields = ['name', 'category', 'price', 'stock'];

  group('row selection', () {
    test('a plain click replaces the selection', () {
      final selection = SelectionState();
      selection.selectRow(1);
      selection.selectRow(3);
      expect(selection.selectedRows, [3]);
    });

    test('ctrl-click toggles rows in and out', () {
      final selection = SelectionState();
      selection.selectRow(1);
      selection.selectRow(3, SelectionModifiers.toggling);
      expect(selection.selectedRows, [1, 3]);
      selection.selectRow(1, SelectionModifiers.toggling);
      expect(selection.selectedRows, [3]);
    });

    test('shift-click selects the span from the anchor', () {
      final selection = SelectionState();
      selection.selectRow(1);
      selection.selectRow(4, SelectionModifiers.extending);
      expect(selection.selectedRows, [1, 2, 3, 4]);
    });

    test('shift-click works backwards from the anchor', () {
      final selection = SelectionState();
      selection.selectRow(4);
      selection.selectRow(1, SelectionModifiers.extending);
      expect(selection.selectedRows, [1, 2, 3, 4]);
    });

    test('a second shift-click re-spans from the same anchor', () {
      final selection = SelectionState();
      selection.selectRow(1);
      selection.selectRow(5, SelectionModifiers.extending);
      selection.selectRow(3, SelectionModifiers.extending);
      expect(selection.selectedRows, [1, 2, 3]);
    });

    test('ctrl-click moves the anchor for the next shift-click', () {
      final selection = SelectionState();
      selection.selectRow(1);
      selection.selectRow(4, SelectionModifiers.toggling);
      selection.selectRow(6, SelectionModifiers.extending);
      expect(selection.selectedRows, [4, 5, 6]);
    });

    test('singleRow mode never holds more than one row', () {
      final selection = SelectionState(mode: SelectionMode.singleRow);
      selection.selectRow(1);
      selection.selectRow(3, SelectionModifiers.toggling);
      expect(selection.selectedRows, [3]);
      selection.selectRow(5, SelectionModifiers.extending);
      expect(selection.selectedRows, [5]);
    });

    test('none mode selects nothing at all', () {
      final selection = SelectionState(mode: SelectionMode.none);
      selection.selectRow(1);
      selection.selectCell(const CellAddress(1, 'name'), fields);
      expect(selection.isEmpty, isTrue);
    });

    test('selectAll takes every row, and clear empties it', () {
      final selection = SelectionState();
      selection.selectAll(4);
      expect(selection.selectedRows, [0, 1, 2, 3]);
      selection.clear();
      expect(selection.isEmpty, isTrue);
      expect(selection.activeCell, isNull);
    });

    test('selectAll does nothing in a single-selection mode', () {
      final selection = SelectionState(mode: SelectionMode.singleRow);
      selection.selectAll(4);
      expect(selection.selectedRows, isEmpty);
    });
  });

  group('cell and range selection', () {
    test('clicking a cell makes it active and starts a one-cell range', () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.selectCell(const CellAddress(2, 'category'), fields);
      expect(selection.activeCell, const CellAddress(2, 'category'));
      expect(selection.range!.rowCount, 1);
      expect(selection.range!.columnCount, 1);
    });

    test('shift-click extends to a rectangle', () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.selectCell(const CellAddress(1, 'name'), fields);
      selection.selectCell(
        const CellAddress(3, 'price'),
        fields,
        SelectionModifiers.extending,
      );
      final range = selection.range!;
      expect(range.firstRow, 1);
      expect(range.lastRow, 3);
      expect(range.coveredFields, ['name', 'category', 'price']);
      expect(range.rowCount, 3);
      expect(range.columnCount, 3);
    });

    test('a range normalises when dragged up and to the left', () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.selectCell(const CellAddress(3, 'price'), fields);
      selection.extendTo(const CellAddress(1, 'name'), fields);
      final range = selection.range!;
      expect(range.firstRow, 1);
      expect(range.lastRow, 3);
      expect(range.coveredFields, ['name', 'category', 'price']);
    });

    test('extending keeps the anchor and moves the focus', () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.selectCell(const CellAddress(1, 'name'), fields);
      selection.extendTo(const CellAddress(2, 'category'), fields);
      selection.extendTo(const CellAddress(3, 'price'), fields);
      expect(selection.range!.anchor, const CellAddress(1, 'name'));
      expect(selection.range!.focus, const CellAddress(3, 'price'));
    });

    test('contains covers the inside and rejects the outside', () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.selectCell(const CellAddress(1, 'name'), fields);
      selection.extendTo(const CellAddress(2, 'category'), fields);
      final range = selection.range!;
      expect(range.contains(const CellAddress(2, 'name')), isTrue);
      expect(range.contains(const CellAddress(3, 'name')), isFalse);
      expect(range.contains(const CellAddress(1, 'price')), isFalse);
    });

    test('cells enumerate row-major, which is what a copy needs', () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.selectCell(const CellAddress(0, 'name'), fields);
      selection.extendTo(const CellAddress(1, 'category'), fields);
      expect(
        selection.range!.cells.map((c) => '${c.row}:${c.field}'),
        ['0:name', '0:category', '1:name', '1:category'],
      );
    });

    test('a cell click in a row mode also selects the row', () {
      final selection = SelectionState();
      selection.selectCell(const CellAddress(2, 'name'), fields);
      expect(selection.selectedRows, [2]);
      expect(selection.range, isNull);
    });

    test('isCellSelected reflects the range and the active cell', () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.selectCell(const CellAddress(1, 'name'), fields);
      selection.extendTo(const CellAddress(1, 'category'), fields);
      expect(
          selection.isCellSelected(const CellAddress(1, 'category')), isTrue);
      expect(selection.isCellSelected(const CellAddress(1, 'price')), isFalse);
    });

    test('extendTo without an anchor behaves as a plain click', () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.extendTo(const CellAddress(2, 'price'), fields);
      expect(selection.activeCell, const CellAddress(2, 'price'));
      expect(selection.range!.rowCount, 1);
    });

    test('a field no longer visible yields an empty range rather than a crash',
        () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.selectCell(const CellAddress(1, 'gone'), ['name', 'price']);
      expect(selection.range!.coveredFields, isEmpty);
      expect(selection.range!.contains(const CellAddress(1, 'name')), isFalse);
    });
  });

  group('clampTo', () {
    test('drops rows that no longer exist', () {
      final selection = SelectionState();
      selection.selectAll(10);
      selection.clampTo(4);
      expect(selection.selectedRows, [0, 1, 2, 3]);
    });

    test('pulls the active cell back into range', () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.selectCell(const CellAddress(9, 'name'), fields);
      selection.clampTo(4);
      expect(selection.activeCell, const CellAddress(3, 'name'));
    });

    test('clears the active cell when every row is gone', () {
      final selection = SelectionState(mode: SelectionMode.cellRange);
      selection.selectCell(const CellAddress(2, 'name'), fields);
      selection.clampTo(0);
      expect(selection.activeCell, isNull);
      expect(selection.selectedRows, isEmpty);
    });

    test('leaves a selection that is still valid alone', () {
      final selection = SelectionState();
      selection.selectRow(1);
      selection.clampTo(10);
      expect(selection.selectedRows, [1]);
    });
  });

  test('CellAddress equality is by row and field', () {
    expect(const CellAddress(1, 'name'), const CellAddress(1, 'name'));
    expect(const CellAddress(1, 'name'), isNot(const CellAddress(2, 'name')));
    // Deliberately equal: the point is that equal addresses collapse in a set.
    // ignore: equal_elements_in_set
    final deduped = {
      const CellAddress(1, 'name'),
      const CellAddress(1, 'name')
    };
    expect(deduped.length, 1);
  });
}
