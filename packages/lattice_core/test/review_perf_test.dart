// The behaviour behind the performance fixes in the 0.4.0 review.
//
// Timings belong in benchmark/; these assert the shapes that made the
// timings what they were - a select-all that builds no set, a load-more that
// asks for a slice, a row band that is a view rather than a copy.
import 'package:lattice_core/advanced.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('select-all', () {
    test('is a flag, not a set of every index', () {
      final selection = SelectionState();
      selection.selectAll(1000000);
      expect(selection.isEverythingSelected, isTrue);
      expect(selection.rowCount, 1000000);
      expect(selection.isRowSelected(999999), isTrue);
      expect(selection.isRowSelected(1000000), isFalse);
      // Nothing to follow across a rebuild.
      expect(selection.followedRows, isEmpty);
      expect(selection.coverageOf(1000000), SelectionCoverage.all);
    });

    test('deselecting one row leaves the rest selected', () {
      final selection = SelectionState();
      selection.selectAll(100);
      selection.selectRow(7, SelectionModifiers.toggling);
      expect(selection.isRowSelected(7), isFalse);
      expect(selection.isRowSelected(8), isTrue);
      expect(selection.rowCount, 99);
      expect(selection.coverageOf(100), SelectionCoverage.some);
      expect(selection.selectedRows, hasLength(99));
      expect(selection.followedRows, [7]);
    });

    test('survives a re-sort with everything selected', () {
      final selection = SelectionState();
      selection.selectAll(5);
      // Reverse the order.
      selection.remapRows((i) => 4 - i, rowCount: 5);
      expect(selection.rowCount, 5);
      expect(selection.isEverythingSelected, isTrue);
    });

    test('a hole follows its row across a re-sort', () {
      final selection = SelectionState();
      selection.selectAll(5);
      selection.selectRow(0, SelectionModifiers.toggling);
      selection.remapRows((i) => 4 - i, rowCount: 5);
      expect(selection.isRowSelected(4), isFalse);
      expect(selection.isRowSelected(0), isTrue);
      expect(selection.rowCount, 4);
    });

    test('clamps when the grid shrinks under it', () {
      final selection = SelectionState();
      selection.selectAll(100);
      selection.clampTo(3);
      expect(selection.rowCount, 3);
      expect(selection.selectedRows, [0, 1, 2]);
    });

    test('the selected list is cached between reads', () {
      final selection = SelectionState();
      selection.selectAll(10);
      final first = selection.selectedRows;
      expect(selection.selectedRows, same(first));
      selection.selectRow(1, SelectionModifiers.toggling);
      expect(selection.selectedRows, isNot(same(first)));
    });
  });

  group('the frozen bands', () {
    test('are views onto the visible rows, not copies of them', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        frozenRowCount: 1,
        frozenRowCountBottom: 1,
      );
      expect(grid.scrollableRows, isA<RowSlice<Product>>());
      expect(grid.scrollableRows, hasLength(grid.rowCount - 2));
      expect(
        (grid.scrollableRows.first as DataGridRow<Product>).index,
        1,
        reason: 'indices stay positions in the full list',
      );
      expect(grid.frozenTopRows, hasLength(1));
      expect(grid.frozenBottomRows, hasLength(1));
      expect(() => grid.scrollableRows[99], throwsRangeError);
      grid.dispose();
    });
  });

  group('the column map', () {
    test('is cached, and dropped when the columns change', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
      );
      final first = grid.columnsByField;
      expect(grid.columnsByField, same(first));
      grid.setColumnVisible('price', false);
      expect(grid.columnsByField, isNot(same(first)));
      expect(grid.column('price')!.visible, isFalse);
      grid.dispose();
    });
  });
}
