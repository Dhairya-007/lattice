import 'dart:async';

import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('first build', () {
    test('a local source resolves rows synchronously in the constructor', () {
      final grid = productGrid();
      expect(grid.isLoading, isFalse);
      expect(grid.rowCount, 6);
      expect(grid.totalCount, 6);
      expect(grid.matchedCount, 6);
    });

    test('visible rows are data rows carrying their source index', () {
      final grid = productGrid();
      final row = grid.visibleRows.first as DataGridRow<Product>;
      expect(row.index, 0);
      expect(row.sourceIndex, 0);
      expect(row.data.name, 'Keyboard');
    });

    test('an initial sort is applied before the first frame', () {
      final grid = productGrid(sorts: [const SortSpec('price')]);
      expect(labelsOf(grid).first, 'Mouse');
    });

    test('an empty source reports empty without being loading', () {
      final grid = productGrid(rows: []);
      expect(grid.isEmpty, isTrue);
      expect(grid.rowCount, 0);
    });
  });

  group('sorting through the controller', () {
    test('toggleSort cycles and notifies', () {
      final grid = productGrid();
      var notifications = 0;
      grid.addListener(() => notifications++);

      grid.toggleSort('price');
      expect(labelsOf(grid).first, 'Mouse');
      grid.toggleSort('price');
      expect(labelsOf(grid).first, 'Laptop');
      grid.toggleSort('price');
      expect(grid.sorts, isEmpty);
      expect(labelsOf(grid).first, 'Keyboard');
      expect(notifications, 3);
    });

    test('a plain toggle replaces the ordering, ctrl-click appends', () {
      final grid = productGrid();
      grid.toggleSort('category');
      grid.toggleSort('price');
      expect(grid.sorts.map((s) => s.field), ['price']);
      grid.toggleSort('category', additive: true);
      expect(grid.sorts.map((s) => s.field), ['price', 'category']);
    });

    test('sortPriority numbers the levels for the header arrows', () {
      final grid = productGrid();
      grid.toggleSort('category');
      grid.toggleSort('price', additive: true);
      expect(grid.sortPriority('category'), 1);
      expect(grid.sortPriority('price'), 2);
      expect(grid.sortPriority('name'), isNull);
      expect(grid.sortFor('price')!.isAscending, isTrue);
    });

    test('an unsortable column ignores header clicks', () {
      final columns = productColumns()
        ..[0] = productColumns()[0].copyWith(sortable: false);
      final grid = GridController<Product>(
        columns: columns,
        dataSource: InMemoryDataSource(sampleProducts()),
      );
      grid.toggleSort('name');
      expect(grid.sorts, isEmpty);
    });

    test('clearSorts restores the source order', () {
      final grid = productGrid(sorts: [const SortSpec('price')]);
      grid.clearSorts();
      expect(labelsOf(grid).first, 'Keyboard');
    });
  });

  group('filtering and search', () {
    test('a column filter narrows the rows and resets to the first page', () {
      final grid = productGrid(pageSize: 2);
      grid.goToPage(2);
      grid.setColumnFilter(
        'category',
        const FilterCondition(
          field: 'category',
          operator: FilterOperator.equals,
          value: 'Input',
        ),
      );
      expect(grid.pageIndex, 0);
      expect(grid.matchedCount, 3);
    });

    test('column filters from several columns combine with AND', () {
      final grid = productGrid();
      grid.setColumnFilter(
        'category',
        const FilterCondition(
          field: 'category',
          operator: FilterOperator.equals,
          value: 'Input',
        ),
      );
      grid.setColumnFilter(
        'price',
        const FilterCondition(
          field: 'price',
          operator: FilterOperator.greaterThan,
          value: 50,
        ),
      );
      expect(labelsOf(grid), ['Keyboard', 'Webcam']);
    });

    test('an empty condition clears that column filter', () {
      final grid = productGrid();
      grid.setColumnFilter(
        'category',
        const FilterCondition(
          field: 'category',
          operator: FilterOperator.equals,
          value: 'Input',
        ),
      );
      expect(grid.matchedCount, 3);
      grid.setColumnFilter('category', null);
      expect(grid.matchedCount, 6);
      expect(grid.columnFilters, isEmpty);
    });

    test('search and filters stack', () {
      final grid = productGrid();
      grid.setColumnFilter(
        'category',
        const FilterCondition(
          field: 'category',
          operator: FilterOperator.equals,
          value: 'Input',
        ),
      );
      grid.setSearch('mouse');
      expect(labelsOf(grid), ['Mouse']);
    });

    test('clearFilters drops filters, search and the structured filter', () {
      final grid = productGrid();
      grid.setSearch('mouse');
      grid.setFilter(const FilterCondition(
        field: 'price',
        operator: FilterOperator.greaterThan,
        value: 1000,
      ));
      expect(grid.rowCount, 0);
      grid.clearFilters();
      expect(grid.search, '');
      expect(grid.filter, isNull);
      expect(grid.rowCount, 6);
    });

    test('setting the same search twice does not re-notify', () {
      final grid = productGrid();
      grid.setSearch('mouse');
      var notifications = 0;
      grid.addListener(() => notifications++);
      grid.setSearch('mouse');
      expect(notifications, 0);
    });

    test('filtering shrinks the selection to rows that still exist', () {
      final grid = productGrid();
      grid.selectAllRows();
      expect(grid.selection.rowCount, 6);
      grid.setSearch('mouse');
      expect(grid.selection.selectedRows, [0]);
    });
  });

  group('paging', () {
    test('pages are sliced and counted from the filtered rows', () {
      final grid = productGrid(pageSize: 2, sorts: [const SortSpec('price')]);
      expect(grid.pageCount, 3);
      expect(labelsOf(grid), ['Mouse', 'Webcam']);
      grid.nextPage();
      expect(grid.pageIndex, 1);
      expect(labelsOf(grid), ['Keyboard', 'Dock']);
      grid.nextPage();
      expect(labelsOf(grid), ['Monitor', 'Laptop']);
      expect(grid.hasNextPage, isFalse);
    });

    test('source indices stay absolute across pages', () {
      final grid = productGrid(pageSize: 2);
      grid.goToPage(1);
      expect(
        (grid.visibleRows.first as DataGridRow<Product>).sourceIndex,
        2,
      );
    });

    test('paging clamps at both ends', () {
      final grid = productGrid(pageSize: 2);
      grid.previousPage();
      expect(grid.pageIndex, 0);
      grid.goToPage(99);
      expect(grid.pageIndex, 2);
      expect(grid.hasPreviousPage, isTrue);
    });

    test('changing the page size keeps the current first row in view', () {
      final grid = productGrid(pageSize: 2);
      grid.goToPage(2);
      grid.setPageSize(4);
      expect(grid.pageIndex, 1);
    });

    test('no page size means one page of everything', () {
      final grid = productGrid();
      expect(grid.pageCount, 1);
      expect(grid.rowCount, 6);
    });

    test('a filter that empties the grid still reports one page', () {
      final grid = productGrid(pageSize: 2);
      grid.setSearch('nothing matches this');
      expect(grid.pageCount, 1);
      expect(grid.rowCount, 0);
    });
  });

  group('grouping', () {
    test('grouping emits headers and indented rows', () {
      final grid = productGrid(groups: [const GroupSpec('category')]);
      expect(grid.isGrouped, isTrue);
      expect(labelsOf(grid).first, 'Compute');
      expect(grid.rowCount, 9);
    });

    test('collapsing a group hides its rows without re-querying', () {
      final grid = productGrid(groups: [const GroupSpec('category')]);
      final header = grid.visibleRows.first as GroupGridRow<Product>;
      grid.toggleGroup(header.path);
      expect(grid.rowCount, 7);
      grid.toggleGroup(header.path);
      expect(grid.rowCount, 9);
    });

    test('collapseAll and expandAll cover every level', () {
      final grid = productGrid(groups: [
        const GroupSpec('category'),
        const GroupSpec('active'),
      ]);
      grid.collapseAllGroups();
      expect(grid.rowCount, 3);
      grid.expandAllGroups();
      expect(grid.rowCount, 3 + 4 + 6);
    });

    test('groupBy adds a level and ungroup removes it', () {
      final grid = productGrid();
      grid.groupBy('category');
      expect(grid.groups.length, 1);
      grid.groupBy('category');
      expect(grid.groups.length, 1, reason: 'no duplicate levels');
      grid.groupBy('active');
      expect(grid.groups.length, 2);
      grid.ungroup('category');
      expect(grid.groups.map((g) => g.field), ['active']);
      grid.clearGroups();
      expect(grid.isGrouped, isFalse);
    });

    test('grouping ignores paging so group counts stay whole', () {
      final grid = productGrid(
        groups: [const GroupSpec('category')],
        pageSize: 2,
      );
      expect(grid.rowCount, 9);
    });

    test('group aggregates are available on the header row', () {
      final grid = productGrid(
        groups: [const GroupSpec('category')],
        aggregations: const [Aggregation.sum('price')],
      );
      final header = grid.visibleRows
          .whereType<GroupGridRow<Product>>()
          .firstWhere((r) => r.label == 'Input');
      expect(header.aggregates['price.sum'], 165);
      expect(grid.aggregates['price.sum'], 2115);
    });

    test('dataAt returns null for a group header row', () {
      final grid = productGrid(groups: [const GroupSpec('category')]);
      expect(grid.dataAt(0), isNull);
      expect(grid.dataAt(1), isNotNull);
    });
  });

  group('columns', () {
    test('resizing is clamped and reflected in the layout', () {
      final grid = productGrid();
      grid.resizeColumn('name', 300);
      expect(grid.widthOf('name'), 300);
      expect(grid.layoutFor(2000).allColumns.first.width, 300);
      grid.resizeColumn('name', 10);
      expect(grid.widthOf('name'), 48);
      grid.resetColumnWidth('name');
      expect(grid.widthOf('name'), 140);
    });

    test('a non-resizable column refuses a resize', () {
      final columns = productColumns()
        ..[0] = productColumns()[0].copyWith(resizable: false);
      final grid = GridController<Product>(
        columns: columns,
        dataSource: InMemoryDataSource(sampleProducts()),
      );
      grid.resizeColumn('name', 300);
      expect(grid.widthOf('name'), 140);
    });

    test('hiding a column removes it from layout and visible fields', () {
      final grid = productGrid();
      grid.setColumnVisible('category', false);
      expect(grid.visibleFields, ['name', 'price', 'stock', 'active']);
      expect(grid.layoutFor(2000).columnCount, 4);
    });

    test('pinning moves a column into a frozen pane', () {
      final grid = productGrid();
      grid.setColumnPin('name', ColumnPin.start);
      final layout = grid.layoutFor(2000);
      expect(layout.leading.map((c) => c.column.field), ['name']);
      expect(layout.scrolling.map((c) => c.column.field).contains('name'),
          isFalse);
    });

    test('moving a column changes display order', () {
      final grid = productGrid();
      grid.moveColumn('name', 2);
      expect(grid.visibleFields.take(3), ['category', 'price', 'name']);
    });

    test('moving to an out-of-range index clamps instead of throwing', () {
      final grid = productGrid();
      grid.moveColumn('name', 99);
      expect(grid.visibleFields.last, 'name');
    });
  });

  group('selection', () {
    test('selectedData maps indices back to rows', () {
      final grid = productGrid();
      grid.selectRow(0);
      grid.selectRow(2, SelectionModifiers.toggling);
      expect(grid.selectedData.map((p) => p.name), ['Keyboard', 'Monitor']);
    });

    test('selectedData skips group headers', () {
      final grid = productGrid(
        groups: [const GroupSpec('category')],
        selectionMode: SelectionMode.multiRow,
      );
      grid.selectAllRows();
      expect(grid.selection.rowCount, 9);
      expect(grid.selectedData.length, 6);
    });

    test('arrow keys move the active cell within bounds', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(0, 'name'));
      grid.moveActiveCell(1, 1);
      expect(grid.selection.activeCell, const CellAddress(1, 'category'));
      grid.moveActiveCell(-5, -5);
      expect(grid.selection.activeCell, const CellAddress(0, 'name'));
      grid.moveActiveCell(99, 99);
      expect(grid.selection.activeCell, const CellAddress(5, 'active'));
    });

    test('shift-arrow extends the range instead of moving it', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(0, 'name'));
      grid.moveActiveCell(2, 0, extend: true);
      expect(grid.selection.range!.rowCount, 3);
      expect(grid.selection.range!.anchor, const CellAddress(0, 'name'));
    });

    test('copying a range yields tab-separated display text', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(0, 'name'));
      grid.extendSelectionTo(const CellAddress(1, 'category'));
      expect(
        grid.copySelectionAsText(),
        'Keyboard\tInput\nMouse\tInput',
      );
    });

    test('copying a range can include its headers', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(0, 'name'));
      grid.extendSelectionTo(const CellAddress(0, 'category'));
      expect(
        grid.copySelectionAsText(includeHeader: true),
        'Name\tCategory\nKeyboard\tInput',
      );
    });

    test('copying selected rows covers every visible column', () {
      final grid = productGrid();
      grid.selectRow(0);
      expect(
        grid.copySelectionAsText(),
        'Keyboard\tInput\t80.00 USD\t12\ttrue',
      );
    });

    test('clearSelection empties everything', () {
      final grid = productGrid();
      grid.selectAllRows();
      grid.clearSelection();
      expect(grid.selection.isEmpty, isTrue);
    });
  });

  group('editing', () {
    test('committing an edit writes through and refreshes the rows', () {
      final grid = productGrid();
      final session = grid.beginEdit(const CellAddress(0, 'name'))!;
      expect(session.value, 'Keyboard');
      grid.updateEdit('Keypad');
      final result = grid.commitEdit();
      expect(result.isCommitted, isTrue);
      expect(grid.editSession, isNull);
      expect(labelsOf(grid).first, 'Keypad');
    });

    test('an edit that changes the sort key moves the row immediately', () {
      final grid = productGrid(sorts: [const SortSpec('price')]);
      expect(labelsOf(grid).first, 'Mouse');
      grid.beginEdit(const CellAddress(0, 'price'));
      grid.updateEdit(9999);
      grid.commitEdit();
      expect(labelsOf(grid).last, 'Mouse');
    });

    test('an invalid edit is rejected and the session stays open', () {
      final grid = productGrid();
      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('');
      final result = grid.commitEdit();
      expect(result.isRejected, isTrue);
      expect(grid.editSession, isNotNull);
      expect(grid.editSession!.error, 'Required');
      expect(labelsOf(grid).first, 'Keyboard');
    });

    test('cancelling leaves the row as it was', () {
      final grid = productGrid();
      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('Nonsense');
      grid.cancelEdit();
      expect(grid.editSession, isNull);
      expect(labelsOf(grid).first, 'Keyboard');
    });

    test('a non-editable column cannot start a session', () {
      final grid = productGrid();
      expect(grid.beginEdit(const CellAddress(0, 'category')), isNull);
      expect(grid.editSession, isNull);
    });

    test('a group header row cannot start a session', () {
      final grid = productGrid(groups: [const GroupSpec('category')]);
      expect(grid.beginEdit(const CellAddress(0, 'name')), isNull);
    });

    test('isEditing identifies just the cell being edited', () {
      final grid = productGrid();
      grid.beginEdit(const CellAddress(0, 'name'));
      expect(grid.isEditing(const CellAddress(0, 'name')), isTrue);
      expect(grid.isEditing(const CellAddress(1, 'name')), isFalse);
    });

    test('committing with no session open is a no-op', () {
      final grid = productGrid();
      expect(grid.commitEdit().outcome, EditOutcome.cancelled);
    });
  });

  group('export', () {
    test('exports the current view, filters and sorts included', () {
      final grid = productGrid(sorts: [const SortSpec('price')]);
      grid.setSearch('Input');
      final csv = grid.exportCsv();
      final rows = csv.split('\r\n').where((l) => l.isNotEmpty).toList();
      expect(rows.length, 4);
      expect(rows[1], startsWith('Mouse'));
    });

    test('exports the grouped shape when the grid is grouped', () {
      final grid = productGrid(groups: [const GroupSpec('category')]);
      expect(grid.exportCsv(), contains('Compute (2)'));
    });
  });

  group('async sources', () {
    test('loading is reported, then the rows arrive', () async {
      final completer = Completer<GridResult<Product>>();
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: AsyncDataSource<Product>((_) => completer.future),
      );
      expect(grid.isLoading, isTrue);
      completer.complete(
        GridResult<Product>(rows: sampleProducts(), totalCount: 6),
      );
      await Future<void>.delayed(Duration.zero);
      expect(grid.isLoading, isFalse);
      expect(grid.rowCount, 6);
    });

    test('a failed fetch surfaces the error and empties the rows', () async {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: AsyncDataSource<Product>(
          (_) async => throw StateError('backend down'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(grid.error, isA<StateError>());
      expect(grid.isLoading, isFalse);
      expect(grid.rowCount, 0);
    });

    test('a slow earlier query cannot overwrite a newer result', () async {
      final completers = <Completer<GridResult<Product>>>[];
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: AsyncDataSource<Product>((query) {
          final completer = Completer<GridResult<Product>>();
          completers.add(completer);
          return completer.future;
        }),
      );

      grid.setSearch('second');
      expect(completers.length, 2);

      // The newer query answers first, then the stale one answers late.
      completers[1].complete(GridResult<Product>(
        rows: [sampleProducts().first],
        totalCount: 1,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(grid.rowCount, 1);

      completers[0].complete(
        GridResult<Product>(rows: sampleProducts(), totalCount: 6),
      );
      await Future<void>.delayed(Duration.zero);
      expect(grid.rowCount, 1, reason: 'the stale response was discarded');
    });

    test('swapping the data source re-queries from the new one', () {
      final grid = productGrid();
      grid.setDataSource(InMemoryDataSource<Product>([
        Product(id: 1, name: 'Only', category: 'X', price: 1),
      ]));
      expect(labelsOf(grid), ['Only']);
    });

    test('source mutations refresh the grid', () {
      final source = InMemoryDataSource<Product>(sampleProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
      );
      source.add(Product(id: 7, name: 'Hub', category: 'Input', price: 30));
      expect(grid.rowCount, 7);
    });

    test('a disposed controller stops listening to its source', () {
      final source = InMemoryDataSource<Product>(sampleProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
      );
      grid.dispose();
      source.add(Product(id: 7, name: 'Hub', category: 'Input', price: 30));
      expect(grid.rowCount, 6);
    });
  });
}
