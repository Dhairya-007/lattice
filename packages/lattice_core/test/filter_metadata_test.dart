import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('operatorsFor', () {
    test('offers text operators for a text column, starting with contains', () {
      final operators = operatorsFor(ColumnType.text);
      expect(operators.first, FilterOperator.contains);
      expect(operators, contains(FilterOperator.startsWith));
    });

    test('never offers a substring test on a number or a date', () {
      for (final type in [ColumnType.number, ColumnType.date]) {
        expect(operatorsFor(type), isNot(contains(FilterOperator.contains)));
        expect(operatorsFor(type), contains(FilterOperator.between));
      }
    });

    test('keeps a boolean column down to the three that mean anything', () {
      expect(operatorsFor(ColumnType.boolean), [
        FilterOperator.equals,
        FilterOperator.isNull,
        FilterOperator.isNotNull,
      ]);
    });

    test('every operator has a label, and only ranges take a second value', () {
      for (final operator in FilterOperator.values) {
        expect(operator.defaultLabel, isNotEmpty);
      }
      expect(FilterOperator.between.needsSecondValue, isTrue);
      expect(FilterOperator.equals.needsSecondValue, isFalse);
      expect(FilterOperator.isEmpty.needsValue, isFalse);
      expect(FilterOperator.isIn.needsValueSet, isTrue);
    });

    test('the controller resolves the set from the column type', () {
      final grid = productGrid();
      expect(grid.operatorsForField('price').first, FilterOperator.equals);
      expect(grid.operatorsForField('name').first, FilterOperator.contains);
      expect(grid.operatorsForField('nope'), isEmpty);
    });
  });

  group('distinctValuesFor', () {
    test('lists each value once, in order', () {
      final grid = productGrid();
      expect(
          grid.distinctValuesFor('category'), ['Compute', 'Display', 'Input']);
    });

    test('covers the rows that match, not the ones filtered away', () {
      final grid = productGrid()..setSearch('mouse');
      expect(grid.distinctValuesFor('category'), ['Input']);
    });

    test('includes null, which is a value a user filters on', () {
      final grid = productGrid();
      expect(grid.distinctValuesFor('stock'), contains(null));
    });

    test('truncates at the limit rather than materialising everything', () {
      final grid = productGrid();
      expect(grid.distinctValuesFor('name', limit: 2).length, 2);
    });

    test('an unknown column is empty, not an error', () {
      expect(productGrid().distinctValuesFor('nope'), isEmpty);
    });

    test('a source that cannot answer returns nothing', () async {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: AsyncDataSource<Product>(
          (q) async =>
              GridResult<Product>(rows: sampleProducts(), totalCount: 6),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(grid.distinctValuesFor('category'), isEmpty);
    });
  });

  group('stats from a result', () {
    test('a remote source can supply the range its rules need', () async {
      final grid = GridController<Product>(
        columns: [
          GridColumn<Product>(
            field: 'price',
            type: ColumnType.number,
            value: (p) => p.price,
            rule: const DataBarRule(fromZero: true),
          ),
        ],
        dataSource: AsyncDataSource<Product>(
          (q) async => GridResult<Product>(
            rows: sampleProducts(),
            totalCount: 6,
            stats: const {
              'price': ColumnStats(min: 0, max: 2000, count: 6, nullCount: 0),
            },
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(grid.statsFor('price').maxNumber, 2000);
      final decoration = grid.decorationFor('price', grid.dataAt(0)!);
      expect(decoration.bar, closeTo(80 / 2000, 0.001));
    });

    test('without them a remote rule has nothing to draw against', () async {
      final grid = GridController<Product>(
        columns: [
          GridColumn<Product>(
            field: 'price',
            type: ColumnType.number,
            value: (p) => p.price,
            rule: const DataBarRule(fromZero: true),
          ),
        ],
        dataSource: AsyncDataSource<Product>(
          (q) async =>
              GridResult<Product>(rows: sampleProducts(), totalCount: 6),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(grid.statsFor('price').isEmpty, isTrue);
    });
  });
}
