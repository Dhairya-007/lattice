import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('without a row key', () {
    test('a selection follows the position, which is all it can do', () {
      final grid = productGrid();
      grid.selectRow(1);
      expect(grid.selectedData.single.name, 'Mouse');
      grid.setSorts([const SortSpec('name')]);
      expect(grid.selectedData.single.name, labelsOf(grid)[1]);
    });

    test('hasRowIdentity reports that rows cannot be recognised', () {
      expect(productGrid().hasRowIdentity, isFalse);
    });
  });

  group('with a row key', () {
    test('a selected row stays selected after a sort moves it', () {
      final grid = productGrid(identified: true);
      grid.selectRow(1);
      expect(grid.selectedData.single.name, 'Mouse');
      grid.setSorts([const SortSpec('name')]);
      expect(grid.selectedData.single.name, 'Mouse');
      expect(
          grid.selection.selectedRows.single, labelsOf(grid).indexOf('Mouse'));
    });

    test('a multi-row selection follows all of its rows', () {
      final grid = productGrid(identified: true);
      grid.selectRow(0);
      grid.selectRow(3, SelectionModifiers.toggling);
      final before = grid.selectedData.map((p) => p.name).toSet();
      grid.setSorts(
          [const SortSpec('price', direction: SortDirection.descending)]);
      expect(grid.selectedData.map((p) => p.name).toSet(), before);
    });

    test('the active cell follows its row and keeps its column', () {
      final grid =
          productGrid(identified: true, selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(2, 'price'));
      expect(grid.dataAt(2)!.name, 'Monitor');
      grid.setSorts([const SortSpec('name')]);
      final active = grid.selection.activeCell!;
      expect(active.field, 'price');
      expect(grid.dataAt(active.row)!.name, 'Monitor');
    });

    test('a selected row filtered out of the view is deselected', () {
      final grid = productGrid(identified: true);
      grid.selectRow(1);
      grid.setSearch('keyboard');
      expect(grid.selection.rowCount, 0);
    });

    test('a selection survives the source replacing its rows', () {
      final rows = sampleProducts();
      final source = InMemoryDataSource<Product>(rows);
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        rowKey: (p) => p.id,
      );
      grid.selectRow(4);
      expect(grid.selectedData.single.id, 5);
      // A refresh that hands back the same rows in a new order, as a server
      // poll would.
      source.setRows(rows.reversed);
      expect(grid.selectedData.single.id, 5);
      expect(grid.selection.selectedRows.single, 1);
    });

    test('an open edit session follows its row', () {
      final grid = productGrid(identified: true);
      final session = grid.beginEdit(const CellAddress(1, 'name'))!;
      expect(session.row.name, 'Mouse');
      grid.updateEdit('Mouse Pro');
      grid.setSorts([const SortSpec('price')]);
      expect(grid.editSession, isNotNull);
      expect(grid.editSession!.value, 'Mouse Pro');
      expect(grid.dataAt(grid.editSession!.cell.row)!.id, 2);
    });

    test('an edit session over a row that disappears is closed', () {
      final grid = productGrid(identified: true);
      grid.beginEdit(const CellAddress(1, 'name'));
      grid.setSearch('keyboard');
      expect(grid.editSession, isNull);
    });

    test('a range selection keeps its ends on the same rows', () {
      final grid = productGrid(
        identified: true,
        selectionMode: SelectionMode.cellRange,
      );
      grid.selectCell(const CellAddress(0, 'name'));
      grid.extendSelectionTo(const CellAddress(2, 'price'));
      expect(grid.selection.range!.rowCount, 3);
      grid.setSorts([const SortSpec('name')]);
      final range = grid.selection.range!;
      final rows = {
        grid.dataAt(range.anchor.row)!.name,
        grid.dataAt(range.focus.row)!.name,
      };
      expect(rows, {'Keyboard', 'Monitor'});
    });

    test('group header rows keep their position, having no identity', () {
      final grid =
          productGrid(identified: true, groups: [const GroupSpec('category')]);
      grid.selectRow(0);
      expect(grid.visibleRows.first, isA<GroupGridRow<Product>>());
      grid.refresh();
      expect(grid.selection.selectedRows, [0]);
    });

    test('a duplicated key resolves to the topmost of the two rows', () {
      final rows = [
        Product(id: 1, name: 'A', category: 'x', price: 1),
        Product(id: 1, name: 'B', category: 'x', price: 2),
      ];
      final source = InMemoryDataSource<Product>(rows);
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        rowKey: (p) => p.id,
      );
      grid.selectRow(1);
      source.setRows(rows);
      expect(grid.selection.selectedRows, [0]);
    });
  });
}
