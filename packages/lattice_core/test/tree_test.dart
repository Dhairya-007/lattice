import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

/// A flat model with a parent reference, which is what a staff table, a file
/// table and a bill of materials all look like.
class Person {
  const Person(this.id, this.name, [this.managerId]);

  final String id;
  final String name;
  final String? managerId;
}

/// A nested model, which is what an API that returns a tree looks like.
class Node {
  const Node(this.id, this.name, [this.children = const []]);

  final String id;
  final String name;
  final List<Node> children;
}

List<Person> staff() => const [
      Person('a', 'Ada'),
      Person('b', 'Bo', 'a'),
      Person('c', 'Cy', 'a'),
      Person('d', 'Di', 'b'),
      Person('e', 'Eve'),
    ];

GridController<Person> staffGrid({
  bool expanded = true,
  List<Person>? rows,
  List<SortSpec> sorts = const [],
}) {
  return GridController<Person>(
    columns: [
      GridColumn<Person>(field: 'name', value: (p) => p.name),
      GridColumn<Person>(field: 'id', value: (p) => p.id),
    ],
    dataSource: InMemoryDataSource<Person>(rows ?? staff()),
    rowKey: (p) => p.id,
    tree: TreeSpec<Person>(parentOf: (p) => p.managerId),
    treeExpandedByDefault: expanded,
    sorts: sorts,
  );
}

List<String> namesOf(GridController<Person> grid) => [
      for (final row in grid.visibleRows)
        '${'  ' * row.depth}${(row as DataGridRow<Person>).data.name}',
    ];

void main() {
  group('a flat model with a parent reference', () {
    test('nests the rows under their parents', () {
      expect(namesOf(staffGrid()), [
        'Ada',
        '  Bo',
        '    Di',
        '  Cy',
        'Eve',
      ]);
    });

    test('marks which rows are parents', () {
      final grid = staffGrid();
      final rows = grid.visibleRows.cast<DataGridRow<Person>>();
      expect(rows[0].hasChildren, isTrue);
      expect(rows[2].hasChildren, isFalse);
      expect(rows.last.hasChildren, isFalse);
    });

    test('a closed branch hides its whole subtree', () {
      final grid = staffGrid();
      grid.toggleRow('a\u001fb');
      expect(namesOf(grid), ['Ada', '  Bo', '  Cy', 'Eve']);
      grid.toggleRow('a');
      expect(namesOf(grid), ['Ada', 'Eve']);
    });

    test('collapseAllRows closes branches the user never opened', () {
      final grid = staffGrid();
      grid.collapseAllRows();
      expect(namesOf(grid), ['Ada', 'Eve']);
      grid.expandAllRows();
      expect(namesOf(grid).length, 5);
    });

    test('starts closed when that is the default', () {
      expect(namesOf(staffGrid(expanded: false)), ['Ada', 'Eve']);
    });

    test('a branch stays open when the rows are re-sorted', () {
      final grid = staffGrid(expanded: false);
      grid.setRowExpanded('a', true);
      expect(namesOf(grid), ['Ada', '  Bo', '  Cy', 'Eve']);
      grid.setSorts([
        const SortSpec('name', direction: SortDirection.descending),
      ]);
      expect(namesOf(grid), ['Eve', 'Ada', '  Cy', '  Bo']);
    });

    test('a row whose parent is filtered out becomes a root', () {
      final grid = staffGrid();
      grid.setColumnFilter(
        'id',
        const FilterCondition(
          field: 'id',
          operator: FilterOperator.notEquals,
          value: 'a',
        ),
      );
      expect(namesOf(grid), ['Bo', '  Di', 'Cy', 'Eve']);
    });

    test('a cycle is rendered once rather than for ever', () {
      final grid = staffGrid(rows: const [
        Person('a', 'Ada', 'b'),
        Person('b', 'Bo', 'a'),
      ]);
      expect(namesOf(grid).length, 2);
    });

    test('a parent reference to a row that does not exist is a root', () {
      final grid = staffGrid(rows: const [Person('x', 'Xu', 'nobody')]);
      expect(namesOf(grid), ['Xu']);
    });

    test('the selection still works by row, not by screen position', () {
      final grid = staffGrid();
      grid.selectRow(1);
      expect(grid.selectedData.single.name, 'Bo');
      grid.toggleRow('a\u001fb');
      expect(grid.selectedData.single.name, 'Bo');
    });

    test('an empty grid is an empty tree', () {
      expect(namesOf(staffGrid(rows: const [])), isEmpty);
    });
  });

  group('a nested model', () {
    test('walks the children each row reports', () {
      const rows = [
        Node('1', 'Assembly', [
          Node('1.1', 'Frame'),
          Node('1.2', 'Motor', [Node('1.2.1', 'Bearing')]),
        ]),
        Node('2', 'Spare'),
      ];
      final grid = GridController<Node>(
        columns: [GridColumn<Node>(field: 'name', value: (n) => n.name)],
        dataSource: InMemoryDataSource<Node>(rows),
        rowKey: (n) => n.id,
        tree: TreeSpec<Node>(childrenOf: (n) => n.children),
      );
      expect(
        [
          for (final row in grid.visibleRows)
            '${'  ' * row.depth}${(row as DataGridRow<Node>).data.name}',
        ],
        [
          'Assembly',
          '  Frame',
          '  Motor',
          '    Bearing',
          'Spare',
        ],
      );
    });
  });

  group('TreeSpec', () {
    test('needs exactly one way of finding the children', () {
      expect(TreeSpec<Person>.new, throwsA(isA<AssertionError>()));
      expect(
        () => TreeSpec<Person>(
          childrenOf: (p) => const [],
          parentOf: (p) => null,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a tree needs a row key to remember its branches', () {
      expect(
        () => GridController<Person>(
          columns: [GridColumn<Person>(field: 'name', value: (p) => p.name)],
          dataSource: InMemoryDataSource<Person>(staff()),
          tree: TreeSpec<Person>(parentOf: (p) => p.managerId),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('grouping wins over a tree', () {
    test('because two hierarchies cannot share one indent', () {
      final grid = staffGrid();
      expect(grid.isTree, isTrue);
      grid.groupBy('id');
      expect(grid.isTree, isFalse);
      expect(grid.visibleRows.first, isA<GroupGridRow<Person>>());
    });
  });
}
