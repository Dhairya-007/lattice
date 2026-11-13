import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  final columns = productColumnMap();

  Object? read(Product row, String field) => columns[field]?.value(row);

  group('buildGroups', () {
    test('buckets rows by one field, ordered by group key', () {
      final groups = buildGroups(
        sampleProducts(),
        [const GroupSpec('category')],
        columns,
      );
      expect(groups.map((g) => g.label), ['Compute', 'Display', 'Input']);
      expect(groups.map((g) => g.rowCount), [2, 1, 3]);
    });

    test('orders group headers descending when asked', () {
      final groups = buildGroups(
        sampleProducts(),
        [const GroupSpec('category', direction: SortDirection.descending)],
        columns,
      );
      expect(groups.first.label, 'Input');
    });

    test('preserves incoming row order inside a bucket', () {
      final sorted = sortRows(
        sampleProducts(),
        [const SortSpec('price', direction: SortDirection.descending)],
        columns,
      );
      final groups =
          buildGroups(sorted, [const GroupSpec('category')], columns);
      final input = groups.firstWhere((g) => g.label == 'Input');
      expect(input.rows.map((p) => p.name), ['Keyboard', 'Webcam', 'Mouse']);
    });

    test('nests multiple levels and gives every node a key path', () {
      final groups = buildGroups(
        sampleProducts(),
        [const GroupSpec('category'), const GroupSpec('active')],
        columns,
      );
      final compute = groups.firstWhere((g) => g.label == 'Compute');
      expect(compute.children.map((g) => g.label), ['false', 'true']);
      expect(compute.children.first.path, 'Compute\u001ffalse');
      expect(compute.isLeafGroup, isFalse);
      expect(compute.rows, isEmpty);
      expect(compute.rowCount, 2);
    });

    test('labels a null key as blank', () {
      final groups =
          buildGroups(sampleProducts(), [const GroupSpec('stock')], columns);
      expect(groups.last.label, '(blank)');
    });

    test('buckets by a derived key with keyOf', () {
      final groups = buildGroups(
        sampleProducts(),
        [
          GroupSpec(
            'price',
            keyOf: (v) => (v! as num) >= 100 ? 'premium' : 'budget',
            labelOf: (k) => '$k tier',
          ),
        ],
        columns,
      );
      expect(groups.map((g) => g.label), ['budget tier', 'premium tier']);
      expect(groups.first.rowCount, 3);
    });

    test('allRows walks the whole subtree in display order', () {
      final groups = buildGroups(
        sampleProducts(),
        [const GroupSpec('category'), const GroupSpec('active')],
        columns,
      );
      expect(groups.expand((g) => g.allRows).length, 6);
    });

    test('returns nothing for no specs or no rows', () {
      expect(buildGroups(sampleProducts(), const [], columns), isEmpty);
      expect(
        buildGroups(<Product>[], [const GroupSpec('category')], columns),
        isEmpty,
      );
    });
  });

  group('aggregates', () {
    test('computes sum, average, min, max and count per group', () {
      final groups = buildGroups(
        sampleProducts(),
        [const GroupSpec('category')],
        columns,
        aggregations: const [
          Aggregation.sum('price'),
          Aggregation.average('price'),
          Aggregation.min('price'),
          Aggregation.max('price'),
          Aggregation.count('price'),
        ],
      );
      final input = groups.firstWhere((g) => g.label == 'Input');
      expect(input.aggregates['price.sum'], 165);
      expect(input.aggregates['price.average'], 55);
      expect(input.aggregates['price.min'], 25);
      expect(input.aggregates['price.max'], 80);
      expect(input.aggregates['price.count'], 3);
    });

    test('numeric aggregates skip nulls like SQL', () {
      final result = computeAggregates(
        sampleProducts(),
        const [Aggregation.sum('stock'), Aggregation.average('stock')],
        read,
      );
      expect(result['stock.sum'], 64);
      expect(result['stock.average'], 64 / 5);
    });

    test('an all-null or empty group aggregates to null, not zero', () {
      final result = computeAggregates(
        [Product(id: 9, name: 'Ghost', category: 'None', price: 0)],
        const [Aggregation.sum('stock'), Aggregation.min('stock')],
        read,
      );
      expect(result['stock.sum'], isNull);
      expect(result['stock.min'], isNull);
      expect(
        computeAggregates(<Product>[], const [Aggregation.sum('price')], read)[
            'price.sum'],
        isNull,
      );
    });

    test('count counts rows while countDistinct counts values', () {
      final result = computeAggregates(
        sampleProducts(),
        const [
          Aggregation('category', type: AggregateType.count),
          Aggregation('category', type: AggregateType.countDistinct),
        ],
        read,
      );
      expect(result['category.count'], 6);
      expect(result['category.countDistinct'], 3);
    });

    test('min and max work on non-numeric values', () {
      final result = computeAggregates(
        sampleProducts(),
        const [Aggregation.min('name'), Aggregation.max('name')],
        read,
      );
      expect(result['name.min'], 'Dock');
      expect(result['name.max'], 'Webcam');
    });

    test('a custom aggregate receives every value', () {
      final result = computeAggregates(
        sampleProducts(),
        [
          Aggregation(
            'name',
            type: AggregateType.custom,
            id: 'initials',
            compute: (values) => values.map((v) => '$v'[0]).join(),
          ),
        ],
        read,
      );
      expect(result['initials'], 'KMMLDW');
    });

    test('no aggregations yields an empty result', () {
      expect(computeAggregates(sampleProducts(), const [], read).isEmpty, isTrue);
    });
  });

  group('flattening and expansion', () {
    List<GroupNode<Product>> twoLevels() => buildGroups(
          sampleProducts(),
          [const GroupSpec('category'), const GroupSpec('active')],
          columns,
        );

    test('expanded groups emit a header then their rows', () {
      final rows = flattenGroups(
        buildGroups(sampleProducts(), [const GroupSpec('category')], columns),
        GroupExpansionState(),
      );
      expect(rows.first, isA<GroupGridRow<Product>>());
      expect(rows.length, 3 + 6);
      expect(rows[1], isA<DataGridRow<Product>>());
      expect((rows[1] as DataGridRow<Product>).depth, 1);
    });

    test('collapsed groups hide their contents but keep the header', () {
      final expansion = GroupExpansionState(expandedByDefault: false);
      final rows = flattenGroups(
        buildGroups(sampleProducts(), [const GroupSpec('category')], columns),
        expansion,
      );
      expect(rows.length, 3);
      expect(rows.every((r) => r is GroupGridRow<Product>), isTrue);
    });

    test('row indices are contiguous and match list position', () {
      final rows = flattenGroups(twoLevels(), GroupExpansionState());
      for (var i = 0; i < rows.length; i++) {
        expect(rows[i].index, i);
      }
    });

    test('toggling one group leaves its siblings alone', () {
      final expansion = GroupExpansionState();
      expansion.toggle('Input');
      final rows = flattenGroups(
        buildGroups(sampleProducts(), [const GroupSpec('category')], columns),
        expansion,
      );
      final labels = [
        for (final r in rows)
          if (r is GroupGridRow<Product>) r.label,
      ];
      expect(labels, ['Compute', 'Display', 'Input']);
      expect(rows.length, 3 + 3);
    });

    test('expansion is keyed by path, so it survives a rebuild', () {
      final expansion = GroupExpansionState();
      expansion.setExpanded('Compute', false);
      final again = flattenGroups(twoLevels(), expansion);
      final compute = again.firstWhere(
        (r) => r is GroupGridRow<Product> && r.label == 'Compute',
      ) as GroupGridRow<Product>;
      expect(compute.expanded, isFalse);
    });

    test('collapseAll closes known paths and expandAll reopens them', () {
      final nodes = twoLevels();
      final expansion = GroupExpansionState();
      expansion.collapseAll(collectGroupPaths(nodes));
      expect(flattenGroups(nodes, expansion).length, 3);
      expansion.expandAll();
      expect(flattenGroups(nodes, expansion).length, greaterThan(3));
    });

    test('collectGroupPaths reaches every level', () {
      expect(collectGroupPaths(twoLevels()).length, 3 + 4);
    });
  });
}
