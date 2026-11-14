// The engine halves of the open feature issues: loading more rows (#25),
// detail panels (#14) and a tree whose children arrive asynchronously (#15).
import 'dart:async';

// The row-list types these assert on are the engine's inner layer.
import 'package:lattice_core/advanced.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// A remote source that serves a slice at a time and says whether more exist.
class SliceBackend extends LatticeDataSource<Product> {
  SliceBackend(this.rows);

  final List<Product> rows;
  final List<int> requestedLimits = [];
  bool _more = true;

  @override
  bool get hasMore => _more;

  @override
  Future<GridResult<Product>> fetch(GridQuery query) async {
    requestedLimits.add(query.limit ?? -1);
    final limit = query.limit ?? rows.length;
    final end = limit > rows.length ? rows.length : limit;
    _more = end < rows.length;
    return GridResult<Product>(
      rows: rows.sublist(0, end),
      totalCount: rows.length,
    );
  }
}

/// A lazily loaded tree: children arrive one branch at a time.
class Folder {
  const Folder(this.id, this.name, {this.isFolder = false});

  final String id;
  final String name;
  final bool isFolder;
}

void main() {
  group('loading more rows', () {
    List<Product> manyProducts() => [
          for (var i = 0; i < 25; i++)
            Product(id: i, name: 'Item $i', category: 'c', price: i),
        ];

    test('asks for one slice first, not the whole table', () async {
      final backend = SliceBackend(manyProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: backend,
        loadMoreSize: 10,
      );
      await Future<void>.delayed(Duration.zero);
      expect(grid.isInfinite, isTrue);
      expect(backend.requestedLimits, [10]);
      expect(grid.rowCount, 10);
      expect(grid.canLoadMore, isTrue);
    });

    test('each load appends a slice rather than replacing the page', () async {
      final backend = SliceBackend(manyProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: backend,
        loadMoreSize: 10,
      );
      await Future<void>.delayed(Duration.zero);

      await grid.loadMore();
      expect(grid.rowCount, 20);
      expect(grid.dataAt(0)!.name, 'Item 0', reason: 'the first slice stayed');
      await grid.loadMore();
      expect(grid.rowCount, 25);
      expect(grid.canLoadMore, isFalse, reason: 'the source said that is all');
    });

    test('a second request while one is in flight is dropped', () async {
      final backend = SliceBackend(manyProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: backend,
        loadMoreSize: 10,
      );
      await Future<void>.delayed(Duration.zero);
      backend.requestedLimits.clear();

      final first = grid.loadMore();
      expect(grid.isLoadingMore, isTrue);
      final second = grid.loadMore();
      await Future.wait([first, second]);
      expect(backend.requestedLimits.length, 1);
    });

    test('changing the query starts again from one slice', () async {
      final backend = SliceBackend(manyProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: backend,
        loadMoreSize: 10,
      );
      await Future<void>.delayed(Duration.zero);
      await grid.loadMore();
      expect(grid.rowCount, 20);

      grid.toggleSort('price');
      await Future<void>.delayed(Duration.zero);
      expect(grid.rowCount, 10, reason: 'slices under the old order are gone');
    });

    test('a local source knows when it has run out', () async {
      final grid = productGrid(rows: sampleProducts());
      expect(grid.isInfinite, isFalse);
      expect(grid.canLoadMore, isFalse);

      final infinite = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(manyProducts()),
        loadMoreSize: 10,
      );
      expect(infinite.rowCount, 10);
      expect(infinite.canLoadMore, isTrue);
      // Awaited, because one request at a time is the rule: a second ask
      // while the first is out is dropped on purpose.
      await infinite.loadMore();
      expect(infinite.rowCount, 20);
      await infinite.loadMore();
      expect(infinite.rowCount, 25);
      expect(infinite.canLoadMore, isFalse);
    });

    test('reload drops back to the first slice', () async {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(manyProducts()),
        loadMoreSize: 10,
      );
      await grid.loadMore();
      expect(grid.rowCount, 20);
      await grid.reload();
      expect(grid.rowCount, 10);
    });

    test('a grouped grid does not load more: grouping needs every row', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(manyProducts()),
        loadMoreSize: 10,
        groups: [const GroupSpec('category')],
      );
      expect(grid.canLoadMore, isFalse);
    });
  });

  group('detail panels', () {
    test('a panel is a row of its own, under the row it belongs to', () {
      final grid = productGrid(identified: true);
      final grid2 = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        rowKey: (p) => p.id,
        detailHeight: 160,
      );
      expect(grid.hasDetailPanels, isFalse);
      expect(grid2.hasDetailPanels, isTrue);

      // Product 2 is Mouse, the second row, so its panel is the third.
      grid2.toggleDetail(2);
      expect(grid2.rowCount, 7);
      final panel = grid2.visibleRows[2] as DetailGridRow<Product>;
      expect(panel.rowKey, 2);
      expect(panel.data.name, 'Mouse');
      expect(panel.height, 160);
      expect(grid2.isDetailOpen(2), isTrue);
    });

    test('rows after a panel are renumbered, so selection still lines up', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        rowKey: (p) => p.id,
        detailHeight: 100,
      );
      grid.toggleDetail(1);
      // Row 0 is Keyboard, row 1 its panel, row 2 Mouse.
      expect(grid.dataAt(0)!.name, 'Keyboard');
      expect(grid.dataAt(1), isNull, reason: 'a panel is not a data row');
      expect(grid.dataAt(2)!.name, 'Mouse');
      for (var i = 0; i < grid.rowCount; i++) {
        expect(grid.visibleRows[i].index, i);
      }
    });

    test('a panel follows its row through a sort', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        rowKey: (p) => p.id,
        detailHeight: 100,
      );
      grid.toggleDetail(4); // Laptop
      grid.setSorts([const SortSpec('name')]);
      final index = grid.visibleRows.indexWhere(
        (r) => r is DetailGridRow<Product>,
      );
      expect((grid.visibleRows[index] as DetailGridRow<Product>).data.name,
          'Laptop');
      expect(grid.dataAt(index - 1)!.name, 'Laptop');
    });

    test('panels work inside groups too', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        rowKey: (p) => p.id,
        detailHeight: 100,
        groups: [const GroupSpec('category')],
      );
      final before = grid.rowCount;
      grid.toggleDetail(1);
      expect(grid.rowCount, before + 1);
      expect(grid.visibleRows.whereType<DetailGridRow<Product>>().length, 1);
    });

    test('closing them all leaves the rows as they were', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        rowKey: (p) => p.id,
        detailHeight: 100,
      );
      grid.setDetailOpen(1, true);
      grid.setDetailOpen(3, true);
      expect(grid.openDetails, {1, 3});
      expect(grid.rowCount, 8);
      grid.closeAllDetails();
      expect(grid.rowCount, 6);
      expect(grid.visibleRows.whereType<DetailGridRow<Product>>(), isEmpty);
    });

    test('an unopened grid pays nothing: the row list stays lazy', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        rowKey: (p) => p.id,
        detailHeight: 100,
      );
      expect(grid.visibleRows, isA<LazyDataRowList<Product>>());
      grid.toggleDetail(1);
      expect(grid.visibleRows, isA<DetailRowList<Product>>());
    });

    test('every index of a list with panels resolves to the right row', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        rowKey: (p) => p.id,
        detailHeight: 100,
      );
      // Panels on the first, a middle and the last row - the three places an
      // arithmetic mapping gets wrong.
      grid.setDetailOpen(1, true);
      grid.setDetailOpen(3, true);
      grid.setDetailOpen(6, true);
      final shape = [
        for (final row in grid.visibleRows)
          row is DetailGridRow<Product> ? 'panel:${row.rowKey}' : 'row',
      ];
      expect(shape, [
        'row',
        'panel:1',
        'row',
        'row',
        'panel:3',
        'row',
        'row',
        'row',
        'panel:6',
      ]);
    });
  });

  group('a tree whose children arrive later', () {
    final loaded = <String>[];

    Future<List<Folder>> loadChildren(Folder row) async {
      loaded.add(row.id);
      if (row.id == 'broken') throw StateError('no permission');
      return [
        Folder('${row.id}/a', 'a'),
        Folder('${row.id}/b', 'b', isFolder: true),
      ];
    }

    GridController<Folder> folderGrid({List<Folder>? roots}) =>
        GridController<Folder>(
          columns: [
            GridColumn<Folder>(field: 'name', value: (f) => f.name),
          ],
          dataSource: InMemoryDataSource<Folder>(
            roots ?? const [Folder('root', 'root', isFolder: true)],
          ),
          rowKey: (f) => f.id,
          tree: TreeSpec<Folder>(
            childrenLoader: loadChildren,
            hasChildren: (f) => f.isFolder,
          ),
          treeExpandedByDefault: false,
        );

    setUp(loaded.clear);

    test('a folder is drawn as expandable before its children exist', () {
      final grid = folderGrid();
      final root = grid.visibleRows.single as DataGridRow<Folder>;
      expect(grid.isLazyTree, isTrue);
      expect(root.hasChildren, isTrue);
      expect(loaded, isEmpty, reason: 'nothing was asked for yet');
    });

    test('opening a branch fetches it, and says so while it waits', () async {
      final grid = folderGrid();
      grid.setRowExpanded('root', true);
      expect(grid.isLoadingChildren('root'), isTrue);
      expect(
        (grid.visibleRows.first as DataGridRow<Folder>).isLoadingChildren,
        isTrue,
      );
      expect(grid.rowCount, 1, reason: 'an open branch is not yet filled');

      await Future<void>.delayed(Duration.zero);
      expect(loaded, ['root']);
      expect(grid.rowCount, 3);
      expect(grid.isLoadingChildren('root'), isFalse);
      expect(grid.dataAt(1)!.name, 'a');
    });

    test('a branch is fetched once, however often it is reopened', () async {
      final grid = folderGrid();
      grid.setRowExpanded('root', true);
      await Future<void>.delayed(Duration.zero);
      grid.setRowExpanded('root', false);
      grid.setRowExpanded('root', true);
      await Future<void>.delayed(Duration.zero);
      expect(loaded, ['root']);
    });

    test('a nested branch stays unfetched until it is opened', () async {
      final grid = folderGrid();
      grid.setRowExpanded('root', true);
      await Future<void>.delayed(Duration.zero);
      expect(loaded, ['root']);

      grid.setRowExpanded('root\u001froot/b', true);
      await Future<void>.delayed(Duration.zero);
      expect(loaded, ['root', 'root/b']);
      expect(grid.rowCount, 5);
    });

    test('a branch that fails reports it and is not retried every frame',
        () async {
      final grid = folderGrid(
        roots: const [Folder('broken', 'broken', isFolder: true)],
      );
      grid.setRowExpanded('broken', true);
      await Future<void>.delayed(Duration.zero);
      expect(grid.childrenError('broken'), isA<StateError>());
      expect(loaded.length, 1);

      grid.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(loaded.length, 1, reason: 'not retried');

      grid.invalidateChildren('broken');
      await Future<void>.delayed(Duration.zero);
      expect(loaded.length, 2, reason: 'asked again when told to');
    });

    test('a spec takes exactly one way of finding children', () {
      expect(
        () => TreeSpec<Folder>(
          childrenOf: (f) => const [],
          childrenLoader: loadChildren,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('the one string the engine owns', () {
    test('the blank group label can be given in any language', () {
      final rows = [
        Product(id: 1, name: 'a', category: 'x', price: 1),
        Product(id: 2, name: 'b', category: 'x', price: 2, stock: 5),
      ];
      final grid = productGrid(
        rows: rows,
        groups: [const GroupSpec('stock', blankLabel: '(leer)')],
      );
      final labels = [
        for (final row in grid.visibleRows)
          if (row is GroupGridRow<Product>) row.label,
      ];
      expect(labels, contains('(leer)'));
    });

    test('it is part of the group identity, so changing it regroups', () {
      const english = GroupSpec('stock');
      const german = GroupSpec('stock', blankLabel: '(leer)');
      expect(english.fingerprint, isNot(german.fingerprint));
      expect(english == german, isFalse);
    });

    test('the validators still take their message, as they always did', () {
      expect(requiredValue('Pflichtfeld')(null), 'Pflichtfeld');
      expect(numberRange(min: 0, message: 'Zu klein')(-1), 'Zu klein');
    });
  });
}
