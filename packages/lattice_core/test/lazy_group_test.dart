// The pipeline stages this exercises are the engine's inner layer.
import 'package:lattice_core/advanced.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// A source that groups the way a database would: it answers with headers and
/// counts, and hands over a group's rows only when asked for them.
class GroupingBackend extends LatticeDataSource<Product> {
  GroupingBackend(this.rows);

  final List<Product> rows;

  /// Which group paths were asked for, in order.
  final List<String> requested = [];
  int headerFetches = 0;
  bool failNext = false;

  @override
  bool get supportsLazyGroups => true;

  @override
  Future<GridResult<Product>> fetch(GridQuery query) async {
    headerFetches++;
    if (!query.lazyGroups) {
      // The eager path: every row, which is the cost lazy grouping avoids.
      return GridResult<Product>(
        rows: List<Product>.of(rows),
        totalCount: rows.length,
      );
    }
    final counts = <String, int>{};
    for (final row in rows) {
      counts.update(row.category, (c) => c + 1, ifAbsent: () => 1);
    }
    final keys = counts.keys.toList()..sort();
    return GridResult<Product>(
      rows: const [],
      totalCount: rows.length,
      groups: [
        for (final key in keys)
          GroupNode<Product>(
            field: 'category',
            key: key,
            label: key,
            depth: 0,
            path: key,
            keys: [GroupKey('category', key)],
            declaredCount: counts[key],
            loaded: false,
          ),
      ],
    );
  }

  @override
  Future<GroupChildren<Product>> fetchGroupChildren(
    GridQuery query,
    GroupNode<Product> node,
  ) async {
    requested.add(node.path);
    if (failNext) {
      failNext = false;
      throw StateError('group unavailable');
    }
    final wanted = node.keys.single.key;
    return GroupChildren<Product>(
      rows: [
        for (final row in rows)
          if (row.category == wanted) row,
      ],
    );
  }
}

GridController<Product> lazyGrid(GroupingBackend backend,
        {bool expanded = false}) =>
    GridController<Product>(
      columns: productColumns(),
      dataSource: backend,
      groups: [const GroupSpec('category')],
      lazyGrouping: true,
      groupsExpandedByDefault: expanded,
    );

void main() {
  group('lazy grouping', () {
    test('asks for headers only, and does not download the rows', () async {
      final backend = GroupingBackend(sampleProducts());
      final grid = lazyGrid(backend);
      await Future<void>.delayed(Duration.zero);

      expect(grid.isLazilyGrouped, isTrue);
      expect(backend.requested, isEmpty);
      expect(grid.rowCount, 3, reason: 'three closed headers');
      final header = grid.visibleRows.first as GroupGridRow<Product>;
      expect(header.isLoaded, isFalse);
      expect(header.label, 'Compute');
      expect(header.rowCount, 2, reason: 'the count the source declared');
    });

    test('fetches a group when it is opened, and only that group', () async {
      final backend = GroupingBackend(sampleProducts());
      final grid = lazyGrid(backend);
      await Future<void>.delayed(Duration.zero);

      grid.setGroupExpanded('Input', true);
      expect(grid.isGroupLoading('Input'), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(backend.requested, ['Input']);
      expect(grid.isGroupLoading('Input'), isFalse);
      expect(labelsOf(grid), [
        'Compute',
        'Display',
        'Input',
        'Keyboard',
        'Mouse',
        'Webcam',
      ]);
    });

    test('an open group with nothing in hand shows its header alone', () async {
      final backend = GroupingBackend(sampleProducts());
      final grid = lazyGrid(backend);
      await Future<void>.delayed(Duration.zero);
      grid.setGroupExpanded('Input', true);
      // Before the fetch resolves.
      expect(grid.rowCount, 3);
      final header = grid.visibleRows
          .whereType<GroupGridRow<Product>>()
          .firstWhere((r) => r.label == 'Input');
      expect(header.expanded, isTrue);
      expect(header.loading, isTrue);
      await Future<void>.delayed(Duration.zero);
    });

    test('a group is fetched once, however often it is reopened', () async {
      final backend = GroupingBackend(sampleProducts());
      final grid = lazyGrid(backend);
      await Future<void>.delayed(Duration.zero);

      grid.toggleGroup('Input');
      await Future<void>.delayed(Duration.zero);
      grid.toggleGroup('Input');
      grid.toggleGroup('Input');
      await Future<void>.delayed(Duration.zero);
      expect(backend.requested, ['Input']);
    });

    test('groups open by default are all fetched on the first render',
        () async {
      final backend = GroupingBackend(sampleProducts());
      lazyGrid(backend, expanded: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(backend.requested.toSet(), {'Compute', 'Display', 'Input'});
    });

    test('a new query drops what was cached for the old one', () async {
      final backend = GroupingBackend(sampleProducts());
      final grid = lazyGrid(backend);
      await Future<void>.delayed(Duration.zero);
      grid.setGroupExpanded('Input', true);
      await Future<void>.delayed(Duration.zero);

      grid.setSearch('o');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(backend.requested, ['Input', 'Input']);
    });

    test('a group that fails reports it and is not retried on every frame',
        () async {
      final backend = GroupingBackend(sampleProducts())..failNext = true;
      final grid = lazyGrid(backend);
      await Future<void>.delayed(Duration.zero);

      grid.setGroupExpanded('Input', true);
      await Future<void>.delayed(Duration.zero);
      expect(grid.groupError('Input'), isA<StateError>());
      expect(backend.requested.length, 1);

      grid.setGroupExpanded('Display', true);
      await Future<void>.delayed(Duration.zero);
      expect(backend.requested.length, 2, reason: 'Input is not retried');

      grid.invalidateGroup('Input');
      await Future<void>.delayed(Duration.zero);
      expect(grid.groupError('Input'), isNull);
      expect(backend.requested.length, 3);
    });

    test('a local source groups in full, having nothing to defer', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        groups: [const GroupSpec('category')],
        lazyGrouping: true,
      );
      expect(grid.isLazilyGrouped, isFalse);
      expect(grid.query.lazyGroups, isFalse);
      expect(grid.rowCount, 3 + 6);
    });

    test('a source that cannot group lazily is asked the eager query',
        () async {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: AsyncDataSource<Product>(
          (q) async => GridResult<Product>(
            rows: sampleProducts(),
            totalCount: 6,
            groups: buildGroups<Product>(
              sampleProducts(),
              [const GroupSpec('category')],
              productColumnMap(),
            ),
          ),
        ),
        groups: [const GroupSpec('category')],
        lazyGrouping: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(grid.isLazilyGrouped, isFalse);
      expect(grid.rowCount, 3 + 6);
    });
  });

  group('a declared count', () {
    test('is what the header reports, even with rows in hand', () {
      final node = GroupNode<Product>(
        field: 'category',
        key: 'Input',
        label: 'Input',
        depth: 0,
        path: 'Input',
        rows: [sampleProducts().first],
        declaredCount: 900,
      );
      expect(node.rowCount, 900);
    });

    test('is kept when the contents are grafted on', () {
      final node = GroupNode<Product>(
        field: 'category',
        key: 'Input',
        label: 'Input',
        depth: 0,
        path: 'Input',
        keys: const [GroupKey('category', 'Input')],
        declaredCount: 3,
        loaded: false,
      );
      final filled = node.withContents(rows: sampleProducts());
      expect(filled.loaded, isTrue);
      expect(filled.rowCount, 3);
      expect(filled.keys, node.keys);
    });
  });

  group('group keys', () {
    test('buildGroups records the path a source would filter on', () {
      final nodes = buildGroups<Product>(
        sampleProducts(),
        [const GroupSpec('category'), const GroupSpec('active')],
        productColumnMap(),
      );
      final leaf = nodes.first.children.first;
      expect(leaf.keys.map((k) => k.field), ['category', 'active']);
      expect(leaf.keys.first.key, 'Compute');
    });
  });
}
