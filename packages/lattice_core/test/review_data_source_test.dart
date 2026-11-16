// Fixes from the 0.4.0 review that live in the data source and the filter.
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// A row model with value equality, which is what records and freezed or
/// equatable classes give you - and what made two equal rows one row.
class Label {
  Label(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is Label && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'Label($text)';
}

void main() {
  group('writing a row that equals another', () {
    List<GridColumn<Label>> columns() => [
          GridColumn<Label>(
            field: 'text',
            value: (l) => l.text,
            setValue: (l, v) => Label('${v ?? ''}'),
          ),
        ];

    test(
        'edits the row that was edited, not the first one that compares '
        'equal', () async {
      final source = InMemoryDataSource<Label>([Label('a'), Label('a')]);
      final grid = GridController<Label>(
        columns: columns(),
        dataSource: source,
      );
      grid.beginEdit(const CellAddress(1, 'text'));
      grid.updateEdit('z');
      grid.commitEdit();
      await grid.pendingWrite;

      expect([for (final row in source.rows) row.text], ['a', 'z']);
      grid.dispose();
    });

    test('a batch write lands one update per row', () async {
      final source = InMemoryDataSource<Label>([Label('a'), Label('a')]);
      await source.commitAll([
        RowUpdate(source.rows[0], Label('x')),
        RowUpdate(source.rows[1], Label('y')),
      ]);
      expect([for (final row in source.rows) row.text], ['x', 'y']);
    });
  });

  group('case-insensitive filters', () {
    GridController<Product> grid() => GridController<Product>(
          columns: productColumns(),
          dataSource: InMemoryDataSource<Product>([
            Product(id: 1, name: 'Apple', category: 'Fruit', price: 5),
            Product(id: 2, name: 'banana', category: 'Fruit', price: 7),
          ]),
        );

    test('equals matches a differently cased value', () {
      final g = grid();
      g.setFilter(const FilterCondition(
        field: 'name',
        operator: FilterOperator.equals,
        value: 'apple',
      ));
      expect([
        for (final r in g.visibleRows.whereType<DataGridRow<Product>>())
          r.data.name
      ], [
        'Apple'
      ]);
      g.dispose();
    });

    test('notEquals excludes a differently cased value', () {
      final g = grid();
      g.setFilter(const FilterCondition(
        field: 'name',
        operator: FilterOperator.notEquals,
        value: 'apple',
      ));
      expect([
        for (final r in g.visibleRows.whereType<DataGridRow<Product>>())
          r.data.name
      ], [
        'banana'
      ]);
      g.dispose();
    });

    test('isIn matches a differently cased value', () {
      final g = grid();
      g.setFilter(const FilterCondition(
        field: 'name',
        operator: FilterOperator.isIn,
        value: ['apple'],
      ));
      expect([
        for (final r in g.visibleRows.whereType<DataGridRow<Product>>())
          r.data.name
      ], [
        'Apple'
      ]);
      g.dispose();
    });

    test('a range includes the value it calls equal', () {
      final g = grid();
      g.setFilter(const FilterCondition(
        field: 'name',
        operator: FilterOperator.greaterOrEqual,
        value: 'apple',
      ));
      expect(
        [
          for (final r in g.visibleRows.whereType<DataGridRow<Product>>())
            r.data.name
        ],
        ['Apple', 'banana'],
      );
      g.dispose();
    });

    test('between covers both of its bounds, typed either way round', () {
      const forwards = FilterCondition(
        field: 'n',
        operator: FilterOperator.between,
        value: 2,
        secondValue: 8,
      );
      const backwards = FilterCondition(
        field: 'n',
        operator: FilterOperator.between,
        value: 8,
        secondValue: 2,
      );
      for (final condition in [forwards, backwards]) {
        expect(condition.matchesRow((_) => 2), isTrue, reason: '$condition');
        expect(condition.matchesRow((_) => 8), isTrue, reason: '$condition');
        expect(condition.matchesRow((_) => 9), isFalse, reason: '$condition');
      }
    });

    test('search folds accents, so creme finds Crème', () {
      final g = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>([
          Product(id: 1, name: 'Crème', category: 'Fruit', price: 5),
        ]),
      );
      g.setSearch('creme');
      expect(g.visibleRows.length, 1);
      g.dispose();
    });
  });

  group('operand coercion', () {
    test('a number column compares a typed operand as a number', () {
      final g = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>([
          Product(id: 1, name: 'a', category: 'c', price: 100),
          Product(id: 2, name: 'b', category: 'c', price: 20),
        ]),
      );
      // As text, '100' < '50' - which is how a filter row's string operand
      // used to hide the wrong rows.
      g.setFilter(const FilterCondition(
        field: 'price',
        operator: FilterOperator.greaterThan,
        value: '50',
      ));
      expect([
        for (final r in g.visibleRows.whereType<DataGridRow<Product>>())
          r.data.price
      ], [
        100
      ]);
      g.dispose();
    });

    test('a date column reads an ISO string operand as a date', () {
      final compiled = const FilterCondition(
        field: 'when',
        operator: FilterOperator.greaterThan,
        value: '2024-06-01T00:00:00.000',
      ).compile(types: {'when': ColumnType.date});
      expect(compiled.test((_) => DateTime(2024, 6, 1, 5)), isTrue);
      expect(compiled.test((_) => DateTime(2024, 5, 31)), isFalse);
    });

    test('a dateOnly condition ignores the time of day', () {
      const condition = FilterCondition(
        field: 'when',
        operator: FilterOperator.equals,
        value: '2024-06-01',
        dateOnly: true,
      );
      final compiled = condition.compile(types: {'when': ColumnType.date});
      expect(compiled.test((_) => DateTime(2024, 6, 1, 14, 30)), isTrue);
      expect(compiled.test((_) => DateTime(2024, 6, 2)), isFalse);
    });
  });

  group('filter identity', () {
    test('two isIn conditions over the same values are equal', () {
      const a = FilterCondition(
        field: 'f',
        operator: FilterOperator.isIn,
        value: ['x', 'y'],
      );
      const b = FilterCondition(
        field: 'f',
        operator: FilterOperator.isIn,
        value: ['x', 'y'],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.fingerprint, b.fingerprint);
    });

    test('two groups over the same children are equal', () {
      final a = FilterGroup.and([
        const FilterCondition(
          field: 'f',
          operator: FilterOperator.equals,
          value: 1,
        ),
      ]);
      final b = FilterGroup.and([
        const FilterCondition(
          field: 'f',
          operator: FilterOperator.equals,
          value: 1,
        ),
      ]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(FilterGroup.or([]), isNot(FilterGroup.and([])));
    });
  });

  group('an isIn over many values', () {
    test('matches without walking every value per row', () {
      final source = InMemoryDataSource<Product>([
        for (var i = 0; i < 2000; i++)
          Product(id: i, name: 'n$i', category: 'c${i % 500}', price: i),
      ]);
      final g = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
      );
      g.setFilter(FilterCondition(
        field: 'category',
        operator: FilterOperator.isIn,
        value: [for (var i = 0; i < 500; i++) 'C$i'],
      ));
      // Folded, so every row matches one of the 500 values.
      expect(g.matchedCount, 2000);
      g.dispose();
    });
  });
}
