// Column, selection and layout fixes from the 0.4.0 review.
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('a filter on a column that is removed', () {
    test('stops hiding every row, and comes back with the column', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
      );
      grid.setColumnFilter(
        'category',
        const FilterCondition(
          field: 'category',
          operator: FilterOperator.equals,
          value: 'Input',
        ),
      );
      final matched = grid.matchedCount;
      expect(matched, greaterThan(0));

      grid.setColumns([
        for (final c in productColumns())
          if (c.field != 'category') c,
      ]);
      expect(grid.rowCount, sampleProducts().length);
      expect(grid.inactiveFields, {'category'});

      grid.setColumns(productColumns());
      expect(grid.matchedCount, matched, reason: 'the filter was only parked');
      expect(grid.inactiveFields, isEmpty);
      grid.dispose();
    });

    test('a sort and a grouping on a missing column are left out too', () {
      final grid = GridController<Product>(
        columns: [
          for (final c in productColumns())
            if (c.field != 'category') c,
        ],
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        sorts: const [SortSpec('category')],
        groups: const [GroupSpec('category')],
      );
      expect(grid.query.sorts, isEmpty);
      expect(grid.query.groups, isEmpty);
      expect(grid.rowCount, sampleProducts().length);
      grid.dispose();
    });
  });

  group('moveColumn', () {
    test('counts positions on screen, not declarations', () {
      final columns = [
        GridColumn<Product>(field: 'a', value: (p) => p.id),
        GridColumn<Product>(
            field: 'hidden', value: (p) => p.id, visible: false),
        GridColumn<Product>(field: 'b', value: (p) => p.name),
        GridColumn<Product>(field: 'c', value: (p) => p.category),
      ];
      final grid = GridController<Product>(
        columns: columns,
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
      );
      expect(grid.visibleFields, ['a', 'b', 'c']);
      grid.moveColumn('a', 2);
      expect(grid.visibleFields, ['b', 'c', 'a']);
      grid.moveColumn('a', 0);
      expect(grid.visibleFields, ['a', 'b', 'c']);
      grid.dispose();
    });
  });

  group('two columns with one field', () {
    test('are refused rather than silently merged', () {
      expect(
        () => GridController<Product>(
          columns: [
            GridColumn<Product>(field: 'name', value: (p) => p.name),
            GridColumn<Product>(field: 'name', value: (p) => p.category),
          ],
          dataSource: InMemoryDataSource<Product>(sampleProducts()),
        ),
        throwsArgumentError,
      );
    });
  });

  group('a cell range', () {
    test('does not outlive the rows it covered', () {
      final source = InMemoryDataSource<Product>(sampleProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        selectionMode: SelectionMode.cellRange,
      );
      grid.selectCell(const CellAddress(0, 'name'));
      grid.extendSelectionTo(CellAddress(grid.rowCount - 1, 'price'));
      expect(grid.selection.range!.lastRow, grid.rowCount - 1);

      source.setRows(sampleProducts().take(2));
      expect(grid.selection.range!.lastRow, lessThan(2));
      final text = grid.copySelectionAsText();
      expect(text.split('\n'), hasLength(2));
      grid.dispose();
    });

    test('contains no cell once its own column has gone', () {
      const range = CellRange(
        anchor: CellAddress(0, 'gone'),
        focus: CellAddress(1, 'gone'),
        fields: ['name', 'price'],
      );
      expect(range.coveredFields, isEmpty);
      expect(range.contains(const CellAddress(0, 'gone')), isFalse);
      expect(range.contains(const CellAddress(0, 'name')), isFalse);
    });
  });

  group('a selected group header', () {
    test('stays on its own group when another collapses', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        groups: const [GroupSpec('category')],
        rowKey: (p) => p.id,
      );
      final headers =
          grid.visibleRows.whereType<GroupGridRow<Product>>().toList();
      final display = headers.firstWhere((h) => h.label == 'Display');
      grid.selection.selectRow(display.index);

      final compute = headers.firstWhere((h) => h.label == 'Compute');
      grid.setGroupExpanded(compute.path, false);

      final selected = grid.selection.rows.single;
      final row = grid.visibleRows[selected] as GroupGridRow<Product>;
      expect(row.label, 'Display');
      grid.dispose();
    });
  });

  group('ColumnFit.stretch', () {
    test('offers what a clamped column refuses to the rest', () {
      final columns = [
        GridColumn<Product>(
          field: 'a',
          value: (p) => p.id,
          width: 100,
          maxWidth: 110,
        ),
        GridColumn<Product>(field: 'b', value: (p) => p.name, width: 100),
        GridColumn<Product>(field: 'c', value: (p) => p.category, width: 100),
      ];
      final layout = computeLayout<Product>(
        columns,
        viewportWidth: 600,
        fit: ColumnFit.stretch,
      );
      final widths = [for (final c in layout.allColumns) c.width];
      expect(widths.first, 110);
      expect(widths[1], closeTo(245, 0.5));
      expect(widths[2], closeTo(245, 0.5));
      expect(widths.reduce((a, b) => a + b), closeTo(600, 0.5));
    });
  });

  group('one listener that throws', () {
    test('does not stop the listeners after it', () {
      final notifier = _Notifier();
      var later = 0;
      var changes = 0;
      notifier.addListener(() => throw StateError('boom'));
      notifier.addListener(() => later++);
      notifier.addChangeListener((_) => changes++);
      expect(
        () => notifier.notifyListeners(changes: const {GridChange.rows}),
        throwsStateError,
        reason: 'the failure is still reported',
      );
      expect(later, 1, reason: 'the second listener still ran');
      expect(changes, 1, reason: 'and so did the change listeners');
    });

    test('a cancellation still reaches every listener', () {
      final signal = FetchSignal();
      var later = 0;
      signal.onCancel(() => throw StateError('boom'));
      signal.onCancel(() => later++);
      expect(signal.cancel, throwsStateError);
      expect(later, 1);
      expect(signal.isCancelled, isTrue);
    });
  });
}

class _Notifier with GridChangeNotifier {}
