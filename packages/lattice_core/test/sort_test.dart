// The pipeline stages this exercises are the engine's inner layer.
import 'package:lattice_core/advanced.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  reviewFixes();

  final columns = productColumnMap();

  group('compareValues', () {
    test('orders nulls last regardless of operand order', () {
      expect(compareValues(null, 5), greaterThan(0));
      expect(compareValues(5, null), lessThan(0));
      expect(compareValues(null, null), 0);
    });

    test('compares numbers, strings, dates and bools naturally', () {
      expect(compareValues(2, 10), lessThan(0));
      expect(compareValues('a', 'b'), lessThan(0));
      expect(
        compareValues(DateTime(2026, 1, 1), DateTime(2026, 2, 1)),
        lessThan(0),
      );
      expect(compareValues(false, true), lessThan(0));
    });

    test('falls back to string order for mismatched types', () {
      expect(compareValues(1, 'a'), isNot(0));
    });

    test('natural order reads embedded numbers', () {
      final values = ['item10', 'item2', 'item1'];
      values.sort(compareValuesNatural);
      expect(values, ['item1', 'item2', 'item10']);
    });

    test('case-insensitive order stays total on a fold tie', () {
      expect(compareValuesCaseInsensitive('Apple', 'apple'), isNot(0));
      expect(compareValuesCaseInsensitive('apple', 'Banana'), lessThan(0));
    });
  });

  group('sortRows', () {
    test('sorts ascending and descending by one column', () {
      final rows = sampleProducts();
      final asc = sortRows(rows, [const SortSpec('price')], columns);
      expect(asc.first.name, 'Mouse');
      final desc = sortRows(
        rows,
        [const SortSpec('price', direction: SortDirection.descending)],
        columns,
      );
      expect(desc.first.name, 'Laptop');
    });

    test('applies later sort levels only to ties in earlier ones', () {
      final sorted = sortRows(
        sampleProducts(),
        [
          const SortSpec('category'),
          const SortSpec('price', direction: SortDirection.descending),
        ],
        columns,
      );
      expect(
        sorted.map((p) => p.name),
        ['Laptop', 'Dock', 'Monitor', 'Keyboard', 'Webcam', 'Mouse'],
      );
    });

    test('is stable for rows the sort cannot distinguish', () {
      final rows = [
        Product(id: 1, name: 'a', category: 'x', price: 1),
        Product(id: 2, name: 'b', category: 'x', price: 1),
        Product(id: 3, name: 'c', category: 'x', price: 1),
      ];
      final sorted = sortRows(rows, [const SortSpec('category')], columns);
      expect(sorted.map((p) => p.id), [1, 2, 3]);
    });

    test('places nulls last in both directions by default', () {
      final rows = sampleProducts();
      expect(
        sortRows(rows, [const SortSpec('stock')], columns).last.stock,
        isNull,
      );
      expect(
        sortRows(
          rows,
          [const SortSpec('stock', direction: SortDirection.descending)],
          columns,
        ).last.stock,
        isNull,
      );
    });

    test('honours NullsPosition.first', () {
      final sorted = sortRows(
        sampleProducts(),
        [const SortSpec('stock', nulls: NullsPosition.first)],
        columns,
      );
      expect(sorted.first.stock, isNull);
    });

    test('uses a column comparator when one is given', () {
      final byLength = {
        'name': GridColumn<Product>(
          field: 'name',
          value: (p) => p.name,
          comparator: (a, b) =>
              (a! as String).length.compareTo((b! as String).length),
        ),
      };
      final sorted =
          sortRows(sampleProducts(), [const SortSpec('name')], byLength);
      expect(sorted.first.name, 'Dock');
    });

    test('leaves rows untouched when no sort applies', () {
      final rows = sampleProducts();
      expect(
        sortRows(rows, const [], columns).map((p) => p.id),
        rows.map((p) => p.id),
      );
      expect(
        sortRows(rows, [const SortSpec('missing')], columns).map((p) => p.id),
        rows.map((p) => p.id),
      );
    });

    test('does not mutate the input list', () {
      final rows = sampleProducts();
      final before = rows.map((p) => p.id).toList();
      sortRows(rows, [const SortSpec('price')], columns);
      expect(rows.map((p) => p.id), before);
    });
  });

  group('cycleSort', () {
    test('walks unsorted to ascending to descending to unsorted', () {
      var sorts = cycleSort(const [], 'price');
      expect(sorts.single.direction, SortDirection.ascending);
      sorts = cycleSort(sorts, 'price');
      expect(sorts.single.direction, SortDirection.descending);
      sorts = cycleSort(sorts, 'price');
      expect(sorts, isEmpty);
    });

    test('replaces the whole ordering on a plain click', () {
      final sorts = cycleSort([const SortSpec('name')], 'price');
      expect(sorts.map((s) => s.field), ['price']);
    });

    test('appends and then removes a level when additive', () {
      var sorts = cycleSort([const SortSpec('name')], 'price', additive: true);
      expect(sorts.map((s) => s.field), ['name', 'price']);
      sorts = cycleSort(sorts, 'price', additive: true);
      expect(sorts.last.direction, SortDirection.descending);
      sorts = cycleSort(sorts, 'price', additive: true);
      expect(sorts.map((s) => s.field), ['name']);
    });
  });

  test('SortSpec round-trips through JSON', () {
    const spec = SortSpec(
      'price',
      direction: SortDirection.descending,
      nulls: NullsPosition.first,
    );
    expect(SortSpec.fromJson(spec.toJson()), spec);
  });
}

// Added with the 0.4.0 review fixes: the default order for a text column, and
// the per-row sort key that makes an expensive order affordable.
void reviewFixes() {
  group('default text ordering', () {
    test('sorts text case-insensitively rather than by code unit', () {
      final rows = [
        {'name': 'banana'},
        {'name': 'Cherry'},
        {'name': 'apple'},
      ];
      final columns = {
        'name': GridColumn<Map<String, Object?>>(field: 'name'),
      };
      final sorted = sortRows(rows, const [SortSpec('name')], columns);
      expect([
        for (final r in sorted) r['name']
      ], [
        'apple',
        'banana',
        'Cherry',
      ]);
    });

    test('keeps two spellings of one word in a stable order', () {
      final rows = [
        {'name': 'apple'},
        {'name': 'Apple'},
      ];
      final columns = {
        'name': GridColumn<Map<String, Object?>>(field: 'name'),
      };
      final sorted = sortRows(rows, const [SortSpec('name')], columns);
      expect(sorted.length, 2);
      // Whichever way round, reversing the direction reverses the result.
      final down = sortRows(
        rows,
        const [SortSpec('name', direction: SortDirection.descending)],
        columns,
      );
      expect(down.first, sorted.last);
    });

    test('leaves a non-text column in its natural order', () {
      final rows = [
        {'n': 10},
        {'n': 9},
      ];
      final columns = {
        'n': GridColumn<Map<String, Object?>>(
          field: 'n',
          type: ColumnType.number,
        ),
      };
      final sorted = sortRows(rows, const [SortSpec('n')], columns);
      expect([for (final r in sorted) r['n']], [9, 10]);
    });

    test('a column comparator still wins over the default', () {
      final rows = [
        {'name': 'apple'},
        {'name': 'Cherry'},
      ];
      final columns = {
        'name': GridColumn<Map<String, Object?>>(
          field: 'name',
          comparator: (a, b) => '$a'.compareTo('$b'),
        ),
      };
      final sorted = sortRows(rows, const [SortSpec('name')], columns);
      expect([for (final r in sorted) r['name']], ['Cherry', 'apple']);
    });
  });

  group('GridColumn.sortKey', () {
    test('orders by the key rather than by the displayed value', () {
      final rows = [
        {'code': 'item10'},
        {'code': 'item2'},
      ];
      final columns = {
        'code': GridColumn<Map<String, Object?>>(
          field: 'code',
          sortKey: (r) => naturalSortKey(r['code']),
        ),
      };
      final sorted = sortRows(rows, const [SortSpec('code')], columns);
      expect([for (final r in sorted) r['code']], ['item2', 'item10']);
    });

    test('is read once per row, not once per comparison', () {
      var reads = 0;
      final rows = [
        for (var i = 0; i < 64; i++) {'n': (i * 37) % 64},
      ];
      final columns = {
        'n': GridColumn<Map<String, Object?>>(
          field: 'n',
          type: ColumnType.number,
          sortKey: (r) {
            reads++;
            return r['n'];
          },
        ),
      };
      sortRows(rows, const [SortSpec('n')], columns);
      expect(reads, 64);
    });
  });
}
