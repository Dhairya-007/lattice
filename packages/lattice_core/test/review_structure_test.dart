// Grouping, tree, saved-view and row-identity fixes from the 0.4.0 review.
import 'package:lattice_core/advanced.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

class Node {
  Node(this.id, this.name, [this.children = const []]);

  final String id;
  final String name;
  final List<Node> children;
}

void main() {
  group('group paths', () {
    test('a null group and a "null" group are two groups', () {
      final rows = [
        {'k': null},
        {'k': 'null'},
      ];
      final columns = {'k': GridColumn<Map<String, Object?>>(field: 'k')};
      final nodes = buildGroups(rows, [const GroupSpec('k')], columns);
      expect(nodes, hasLength(2));
      expect(nodes[0].path, isNot(nodes[1].path));
    });

    test('a numeric group and a text group are two groups', () {
      final rows = [
        {'k': 1},
        {'k': '1'},
      ];
      final columns = {'k': GridColumn<Map<String, Object?>>(field: 'k')};
      final nodes = buildGroups(rows, [const GroupSpec('k')], columns);
      expect(nodes, hasLength(2));
      expect(nodes[0].path, isNot(nodes[1].path));
    });

    test('expansion does not leak between grouping fields', () {
      final rows = [
        {'x': true, 'y': true},
        {'x': false, 'y': false},
      ];
      final columns = {
        'x': GridColumn<Map<String, Object?>>(
          field: 'x',
          type: ColumnType.boolean,
        ),
        'y': GridColumn<Map<String, Object?>>(
          field: 'y',
          type: ColumnType.boolean,
        ),
      };
      final grid = GridController<Map<String, Object?>>(
        columns: columns.values.toList(),
        dataSource: InMemoryDataSource<Map<String, Object?>>(rows),
        groups: const [GroupSpec('x')],
      );
      final trueGroup = grid.visibleRows
          .whereType<GroupGridRow<Map<String, Object?>>>()
          .firstWhere((r) => r.key == true);
      grid.setGroupExpanded(trueGroup.path, false);

      grid.setGroups(const [GroupSpec('y')]);
      final yTrue = grid.visibleRows
          .whereType<GroupGridRow<Map<String, Object?>>>()
          .firstWhere((r) => r.key == true);
      expect(yTrue.expanded, isTrue, reason: 'a fresh grouping starts open');
      grid.dispose();
    });

    test('a key containing the path separator cannot forge a boundary', () {
      final rows = [
        {'k': 'a\u001fb'},
        {'k': 'a'},
      ];
      final columns = {'k': GridColumn<Map<String, Object?>>(field: 'k')};
      final nodes = buildGroups(rows, [const GroupSpec('k')], columns);
      final paths = {for (final n in nodes) n.path};
      expect(paths, hasLength(2));
      for (final path in paths) {
        expect(path.split('\u001f'), hasLength(1));
      }
    });
  });

  group('group header order', () {
    test('follows the column comparator', () {
      const order = ['High', 'Medium', 'Low'];
      final rows = [
        for (final p in ['Low', 'High', 'Medium']) {'priority': p},
      ];
      final columns = {
        'priority': GridColumn<Map<String, Object?>>(
          field: 'priority',
          comparator: (a, b) =>
              order.indexOf('$a').compareTo(order.indexOf('$b')),
        ),
      };
      final nodes = buildGroups(rows, [const GroupSpec('priority')], columns);
      expect([for (final n in nodes) n.label], order);
    });

    test('keeps the blank group last when the headers are reversed', () {
      final rows = [
        {'k': 'a'},
        {'k': null},
        {'k': 'b'},
      ];
      final columns = {'k': GridColumn<Map<String, Object?>>(field: 'k')};
      final down = buildGroups(
        rows,
        [const GroupSpec('k', direction: SortDirection.descending)],
        columns,
      );
      expect([for (final n in down) n.key], ['b', 'a', null]);

      final nullsFirst = buildGroups(
        rows,
        [const GroupSpec('k', nulls: NullsPosition.first)],
        columns,
      );
      expect([for (final n in nullsFirst) n.key], [null, 'a', 'b']);
    });
  });

  group('collapseAll', () {
    test('closes a group that only appears later', () {
      final source = InMemoryDataSource<Product>(sampleProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        groups: const [GroupSpec('category')],
      );
      grid.collapseAllGroups();
      final headers = grid.visibleRows.whereType<GroupGridRow<Product>>();
      expect(headers.every((h) => !h.expanded), isTrue);

      // A category nobody has seen yet must arrive closed too.
      source.add(Product(id: 99, name: 'Lamp', category: 'Light', price: 9));
      final light = grid.visibleRows
          .whereType<GroupGridRow<Product>>()
          .firstWhere((h) => h.label == 'Light');
      expect(light.expanded, isFalse);
      grid.dispose();
    });

    test('survives a saved view', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        groups: const [GroupSpec('category')],
      );
      grid.collapseAllGroups();
      final state = GridViewState.fromJson(grid.saveState().toJson());

      final restored = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        groups: const [GroupSpec('category')],
      )..restoreState(state);
      expect(
        restored.visibleRows
            .whereType<GroupGridRow<Product>>()
            .every((h) => !h.expanded),
        isTrue,
      );
      grid.dispose();
      restored.dispose();
    });
  });

  group('sourceIndex', () {
    test('is the position in the source, not in the sorted result', () {
      final products = sampleProducts();
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(products),
        sorts: const [
          SortSpec('price', direction: SortDirection.descending),
        ],
      );
      final first = grid.visibleRows.first as DataGridRow<Product>;
      expect(first.sourceIndex, products.indexOf(first.data));
      grid.dispose();
    });

    test('is reported for grouped rows too', () {
      final products = sampleProducts();
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(products),
        groups: const [GroupSpec('category')],
      );
      for (final row in grid.visibleRows.whereType<DataGridRow<Product>>()) {
        expect(row.sourceIndex, products.indexOf(row.data));
      }
      grid.dispose();
    });
  });

  group('a deep tree', () {
    // Built from the leaf upwards, because building it the other way round
    // would overflow the stack in the test rather than in the code it tests.
    List<Node> chain(int depth) {
      var node = Node('n$depth', 'n$depth');
      for (var level = depth - 1; level >= 0; level--) {
        node = Node('n$level', 'n$level', [node]);
      }
      return [node];
    }

    test('flattens 10,000 levels without overflowing the stack', () {
      final expansion = GroupExpansionState();
      final rows = flattenTree<Node>(
        rows: chain(10000),
        spec: TreeSpec<Node>(childrenOf: (n) => n.children),
        keyOf: (n) => n.id,
        expansion: expansion,
      );
      expect(rows, hasLength(10001));
    });

    test('places a collapsed chain without overflowing the stack', () {
      final expansion = GroupExpansionState(expandedByDefault: false);
      final rows = flattenTree<Node>(
        rows: chain(20000),
        spec: TreeSpec<Node>(childrenOf: (n) => n.children),
        keyOf: (n) => n.id,
        expansion: expansion,
      );
      expect(rows, hasLength(1));
    });

    test('keeps the path length flat as the tree deepens', () {
      final expansion = GroupExpansionState();
      final rows = flattenTree<Node>(
        rows: chain(2000),
        spec: TreeSpec<Node>(childrenOf: (n) => n.children),
        keyOf: (n) => n.id,
        expansion: expansion,
      );
      final deepest = rows.last as DataGridRow<Node>;
      // The old path repeated every ancestor, so this was ~14KB.
      expect(deepest.treePath.length, lessThan(16));
    });
  });

  group('a nested tree', () {
    test('sorts the children of each level', () {
      final roots = [
        Node('a', 'Ada', [Node('c', 'Cy'), Node('b', 'Bo')]),
      ];
      final grid = GridController<Node>(
        columns: [GridColumn<Node>(field: 'name', value: (n) => n.name)],
        dataSource: InMemoryDataSource<Node>(roots),
        rowKey: (n) => n.id,
        tree: TreeSpec<Node>(childrenOf: (n) => n.children),
        sorts: const [SortSpec('name')],
      );
      expect(
        [
          for (final r in grid.visibleRows.whereType<DataGridRow<Node>>())
            r.data.name,
        ],
        ['Ada', 'Bo', 'Cy'],
      );
      grid.dispose();
    });

    test('flattenNestedRows gives the pipeline every row', () {
      final roots = [
        Node('a', 'Ada', [Node('b', 'Bo')]),
      ];
      final flat = flattenNestedRows<Node>(
        roots,
        childrenOf: (n) => n.children,
        keyOf: (n) => n.id,
      );
      final grid = GridController<Node>(
        columns: [GridColumn<Node>(field: 'name', value: (n) => n.name)],
        dataSource: InMemoryDataSource<Node>(flat.rows),
        rowKey: (n) => n.id,
        tree: TreeSpec<Node>(parentOf: flat.parentOf),
      );
      expect(grid.rowCount, 2);
      // The search a nested model could not answer.
      grid.setSearch('Bo');
      expect(grid.rowCount, 1);
      expect(grid.dataAt(0)!.name, 'Bo');
      grid.dispose();
    });
  });

  group('a saved view that is partly unreadable', () {
    test('restores what it can and reports the rest', () {
      final warnings = <String>[];
      final state = GridViewState.fromJson({
        'sorts': [
          {'field': 'name', 'dir': 'ascending'},
          {'dir': 'descending'},
        ],
        'columns': [
          {'field': 'name', 'width': 120},
          {'width': 80},
        ],
      }, warnings: warnings);
      expect(state.sorts, hasLength(1));
      expect(state.columns, hasLength(1));
      expect(warnings, hasLength(2));
    });

    test('an isIn condition whose value is not a list is readable', () {
      final state = GridViewState.fromJson({
        'columnFilters': {
          'name': {'field': 'name', 'op': 'isIn', 'value': 'a'},
        },
      });
      expect(state.columnFilters['name']!.value, ['a']);
    });

    test('a future schema version is still refused', () {
      expect(
        () => GridViewState.fromJson({'v': 99}),
        throwsFormatException,
      );
    });
  });
}
