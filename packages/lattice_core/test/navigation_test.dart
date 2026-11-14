import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('paging the active cell', () {
    test('PageDown moves a screenful down and stops at the last row', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(0, 'name'));
      grid.movePages(1, rowsPerPage: 4);
      expect(grid.selection.activeCell, const CellAddress(4, 'name'));
      grid.movePages(1, rowsPerPage: 4);
      expect(grid.selection.activeCell, const CellAddress(5, 'name'));
    });

    test('PageUp stops at the first row', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(3, 'name'));
      grid.movePages(-1, rowsPerPage: 10);
      expect(grid.selection.activeCell, const CellAddress(0, 'name'));
    });

    test('a viewport of no rows is not a move', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(2, 'name'));
      grid.movePages(1, rowsPerPage: 0);
      expect(grid.selection.activeCell, const CellAddress(2, 'name'));
    });

    test('shift-PageDown extends the range instead of replacing it', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(0, 'name'));
      grid.movePages(1, rowsPerPage: 3, extend: true);
      expect(grid.selection.range!.rowCount, 4);
    });
  });

  group('Home and End', () {
    test('move to the first and last column of the row', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(2, 'price'));
      grid.moveToLineEdge(start: true);
      expect(grid.selection.activeCell, const CellAddress(2, 'name'));
      grid.moveToLineEdge(start: false);
      expect(grid.selection.activeCell, const CellAddress(2, 'active'));
    });

    test('follow screen order, so pinning moves where Home lands', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.setColumnPin('stock', ColumnPin.start);
      grid.selectCell(const CellAddress(0, 'price'));
      grid.moveToLineEdge(start: true);
      expect(grid.selection.activeCell!.field, 'stock');
    });

    test('ctrl-Home and ctrl-End go to the corners of the grid', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(2, 'price'));
      grid.moveToGridEdge(start: false);
      expect(grid.selection.activeCell, const CellAddress(5, 'active'));
      grid.moveToGridEdge(start: true);
      expect(grid.selection.activeCell, const CellAddress(0, 'name'));
    });

    test('an empty grid is not a move', () {
      final grid = productGrid(rows: []);
      grid.moveToGridEdge(start: true);
      grid.moveToLineEdge(start: true);
      expect(grid.selection.activeCell, isNull);
    });
  });

  group('Tab between editable cells', () {
    test('skips the columns that cannot be edited', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(0, 'name'));
      expect(grid.moveToNextEditableCell(), const CellAddress(0, 'price'));
      expect(grid.moveToNextEditableCell(), const CellAddress(1, 'name'));
    });

    test('shift-Tab walks back', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(1, 'name'));
      expect(
        grid.moveToNextEditableCell(backwards: true),
        const CellAddress(0, 'price'),
      );
    });

    test('wraps round at the end, or stops if told not to', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(5, 'price'));
      expect(grid.moveToNextEditableCell(wrap: false), isNull);
      expect(grid.selection.activeCell, const CellAddress(5, 'price'));
      expect(grid.moveToNextEditableCell(), const CellAddress(0, 'name'));
    });

    test('starts from a non-editable column at the next editable one', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(0, 'category'));
      expect(grid.moveToNextEditableCell(), const CellAddress(0, 'price'));
    });

    test('steps over a group header rather than landing on it', () {
      final grid = productGrid(
        groups: [const GroupSpec('category')],
        selectionMode: SelectionMode.cellRange,
      );
      final rows = grid.visibleRows;
      final lastOfGroup = rows.indexWhere(
            (r) => r is GroupGridRow<Product> && r.index > 0,
          ) -
          1;
      grid.selectCell(CellAddress(lastOfGroup, 'price'));
      final next = grid.moveToNextEditableCell()!;
      expect(grid.dataAt(next.row), isNotNull);
    });

    test('a grid with no editable column has nowhere to go', () {
      final grid = GridController<Product>(
        columns: [GridColumn<Product>(field: 'name', value: (p) => p.name)],
        dataSource: InMemoryDataSource(sampleProducts()),
        selectionMode: SelectionMode.cellRange,
      );
      expect(grid.moveToNextEditableCell(), isNull);
    });
  });

  group('Aggregation.format', () {
    test('a count reads as a count and a sum as its own units', () {
      const count = Aggregation.count('price');
      const sum = Aggregation.sum('price', format: _money);
      expect(count.formatted(count.apply([1, 2, 3])), '3');
      expect(sum.formatted(sum.apply([1, 2, 3])), '6.00 USD');
    });

    test('a fractional result is cut to two places, a whole one to none', () {
      const average = Aggregation.average('price');
      expect(average.formatted(average.apply([1, 2])), '1.50');
      expect(average.formatted(average.apply([2, 4])), '3');
      expect(average.formatted(average.apply([1, 2, 2])), '1.67');
    });

    test('an empty group formats as empty, not as zero', () {
      const sum = Aggregation.sum('price');
      expect(sum.formatted(sum.apply(const [])), '');
    });

    test('a non-numeric result still prints', () {
      const first = Aggregation('name', type: AggregateType.first);
      expect(first.formatted(first.apply(['a', 'b'])), 'a');
    });
  });
}

String _money(Object? value) =>
    value == null ? '' : '${(value as num).toStringAsFixed(2)} USD';
