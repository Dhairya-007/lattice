import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('coverage', () {
    test('reports none, some and all', () {
      final selection = SelectionState();
      expect(selection.coverageOf(3), SelectionCoverage.none);

      selection.selectRow(0);
      expect(selection.coverageOf(3), SelectionCoverage.some);

      selection.selectAll(3);
      expect(selection.coverageOf(3), SelectionCoverage.all);
    });

    test('an empty grid is never partly selected', () {
      final selection = SelectionState()..selectRow(0);
      expect(selection.coverageOf(0), SelectionCoverage.none);
    });

    test('stale indices cannot make a partial selection look complete', () {
      final selection = SelectionState()..selectAll(10);
      // The grid shrank to 3 rows; 7 of the selected indices no longer exist.
      expect(selection.coverageOf(3), SelectionCoverage.all);

      final partial = SelectionState()
        ..selectRow(7, SelectionModifiers.toggling)
        ..selectRow(8, SelectionModifiers.toggling);
      expect(partial.coverageOf(3), SelectionCoverage.none);
    });

    test('one row of one is complete', () {
      final selection = SelectionState()..selectRow(0);
      expect(selection.coverageOf(1), SelectionCoverage.all);
    });
  });

  group('through the controller', () {
    test('toggleSelectAll selects everything, then clears it', () {
      final grid = productGrid();
      expect(grid.selectionCoverage, SelectionCoverage.none);

      grid.toggleSelectAll();
      expect(grid.selectionCoverage, SelectionCoverage.all);
      expect(grid.selection.rowCount, 6);

      grid.toggleSelectAll();
      expect(grid.selectionCoverage, SelectionCoverage.none);
    });

    test('a partial selection becomes a full one, not an empty one', () {
      final grid = productGrid();
      grid.selectRow(2);
      expect(grid.selectionCoverage, SelectionCoverage.some);
      grid.toggleSelectAll();
      expect(grid.selectionCoverage, SelectionCoverage.all);
    });

    test('a row checkbox toggles only its own row', () {
      final grid = productGrid();
      grid.setRowSelected(1, true);
      grid.setRowSelected(3, true);
      expect(grid.selection.selectedRows, [1, 3]);

      grid.setRowSelected(1, false);
      expect(grid.selection.selectedRows, [3]);
    });

    test('setting a row to the state it already has does nothing', () {
      final grid = productGrid();
      grid.setRowSelected(1, true);
      var notified = 0;
      grid.addListener(() => notified++);
      grid.setRowSelected(1, true);
      expect(notified, 0);
      expect(grid.selection.selectedRows, [1]);
    });

    test('a row checkbox does not clear the rest, unlike a row click', () {
      final grid = productGrid();
      grid.setRowSelected(0, true);
      grid.setRowSelected(1, true);
      expect(grid.selection.rowCount, 2);

      // A plain click is the replacing gesture.
      grid.selectRow(4);
      expect(grid.selection.selectedRows, [4]);
    });

    test('coverage follows a filter shrinking the grid', () {
      final grid = productGrid();
      grid.selectAllRows();
      expect(grid.selectionCoverage, SelectionCoverage.all);

      grid.setSearch('Input');
      // Selection was clamped to the three remaining rows.
      expect(grid.rowCount, 3);
      expect(grid.selectionCoverage, SelectionCoverage.all);
    });

    test('grouping counts header rows, which are selectable too', () {
      final grid = productGrid(groups: [const GroupSpec('category')]);
      grid.toggleSelectAll();
      expect(grid.selection.rowCount, 9);
      expect(grid.selectedData.length, 6);
    });

    test('nothing is selectable in SelectionMode.none', () {
      final grid = productGrid(selectionMode: SelectionMode.none);
      grid.toggleSelectAll();
      expect(grid.selectionCoverage, SelectionCoverage.none);
      grid.setRowSelected(0, true);
      expect(grid.selection.isEmpty, isTrue);
    });
  });
}
