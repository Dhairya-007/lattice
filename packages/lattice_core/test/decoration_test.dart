// The pipeline stages this exercises are the engine's inner layer.
import 'package:lattice_core/advanced.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('ColumnStats', () {
    test('finds the range and counts nulls separately', () {
      final stats = computeColumnStats([5, 1, 9, null, 3]);
      expect(stats.min, 1);
      expect(stats.max, 9);
      expect(stats.count, 4);
      expect(stats.nullCount, 1);
      expect(stats.sum, 18);
      expect(stats.mean, 4.5);
    });

    test('works on non-numeric values, leaving sum unset', () {
      final stats = computeColumnStats(['pear', 'apple', 'fig']);
      expect(stats.min, 'apple');
      expect(stats.max, 'pear');
      expect(stats.sum, isNull);
      expect(stats.mean, isNull);
    });

    test('an empty column is empty, not zero', () {
      final stats = computeColumnStats([null, null]);
      expect(stats.isEmpty, isTrue);
      expect(stats.min, isNull);
      expect(stats.mean, isNull);
    });

    test('fractionOf places a value in the range', () {
      final stats = computeColumnStats([0, 50, 100]);
      expect(stats.fractionOf(0), 0);
      expect(stats.fractionOf(50), 0.5);
      expect(stats.fractionOf(100), 1);
    });

    test('fractionOf clamps outside the range and rejects non-numbers', () {
      final stats = computeColumnStats([10, 20]);
      expect(stats.fractionOf(-5), 0);
      expect(stats.fractionOf(500), 1);
      expect(stats.fractionOf('x'), isNull);
      expect(stats.fractionOf(null), isNull);
    });

    test('a column where every value is equal has no usable range', () {
      final stats = computeColumnStats([7, 7, 7]);
      expect(stats.fractionOf(7), 1);
      expect(stats.fractionOf(1), isNull);
    });
  });

  group('DataBarRule', () {
    final stats = computeColumnStats([0, 25, 50, 75, 100]);

    test('fills in proportion to the column range', () {
      const rule = DataBarRule();
      expect(rule.decorate(50, stats)!.bar, 0.5);
      expect(rule.decorate(100, stats)!.bar, 1);
    });

    test('keeps a sliver visible for a small non-zero value', () {
      const rule = DataBarRule(minimumFraction: 0.05);
      expect(rule.decorate(1, stats)!.bar, 0.05);
      expect(rule.decorate(0, stats)!.bar, 0);
    });

    test('fromZero measures against the maximum, not the minimum', () {
      final offset = computeColumnStats([80, 90, 100]);
      expect(const DataBarRule().decorate(90, offset)!.bar, 0.5);
      expect(
        const DataBarRule(fromZero: true).decorate(90, offset)!.bar,
        closeTo(0.9, 0.0001),
      );
    });

    test('leaves non-numeric and unmeasurable cells alone', () {
      expect(const DataBarRule().decorate('x', stats), isNull);
      expect(
        const DataBarRule().decorate(5, ColumnStats.empty),
        isNull,
      );
    });
  });

  group('ColorScaleRule', () {
    final stats = computeColumnStats([0, 100]);

    test('tones the ends differently', () {
      const rule = ColorScaleRule();
      expect(rule.decorate(100, stats)!.tone, CellTone.severe);
      expect(rule.decorate(0, stats)!.tone, CellTone.positive);
    });

    test('intensity is strongest at the ends and quiet in the middle', () {
      const rule = ColorScaleRule();
      expect(rule.decorate(100, stats)!.intensity, 1);
      expect(rule.decorate(0, stats)!.intensity, 1);
      expect(rule.decorate(50, stats)!.intensity, lessThan(0.1));
    });

    test('reverse swaps which end is which', () {
      const rule = ColorScaleRule(reverse: true);
      expect(rule.decorate(100, stats)!.tone, CellTone.positive);
      expect(rule.decorate(0, stats)!.tone, CellTone.severe);
    });

    test('an off-centre midpoint moves the crossover', () {
      const rule = ColorScaleRule(midpoint: 0.9);
      expect(rule.decorate(80, stats)!.tone, CellTone.positive);
      expect(rule.decorate(95, stats)!.tone, CellTone.severe);
    });
  });

  group('ThresholdRule', () {
    final stats = computeColumnStats([0, 100]);

    test('fires at and above the threshold', () {
      const rule = ThresholdRule(threshold: 50);
      expect(rule.decorate(49, stats), isNull);
      expect(rule.decorate(50, stats)!.tone, CellTone.severe);
      expect(rule.decorate(51, stats)!.tone, CellTone.severe);
    });

    test('can fire below instead', () {
      const rule = ThresholdRule(threshold: 50, above: false);
      expect(rule.decorate(49, stats)!.tone, CellTone.severe);
      expect(rule.decorate(51, stats), isNull);
    });

    test('works on dates as well as numbers', () {
      final rule = ThresholdRule(threshold: DateTime(2026, 6, 1));
      expect(rule.decorate(DateTime(2026, 7, 1), stats), isNotNull);
      expect(rule.decorate(DateTime(2026, 5, 1), stats), isNull);
    });

    test('never fires on null', () {
      expect(const ThresholdRule(threshold: 0).decorate(null, stats), isNull);
    });
  });

  group('ValueToneRule', () {
    final stats = ColumnStats.empty;

    test('maps known values and ignores the rest', () {
      const rule = ValueToneRule({
        'error': CellTone.severe,
        'warn': CellTone.caution,
      });
      expect(rule.decorate('error', stats)!.tone, CellTone.severe);
      expect(rule.decorate('warn', stats)!.tone, CellTone.caution);
      expect(rule.decorate('info', stats), isNull);
    });

    test('ignores case unless asked not to', () {
      const rule = ValueToneRule({'error': CellTone.severe});
      expect(rule.decorate('ERROR', stats)!.tone, CellTone.severe);
      expect(
        const ValueToneRule(
          {'error': CellTone.severe},
          caseSensitive: true,
        ).decorate('ERROR', stats),
        isNull,
      );
    });

    test('maps non-string values too', () {
      const rule = ValueToneRule({false: CellTone.caution});
      expect(rule.decorate(false, stats)!.tone, CellTone.caution);
      expect(rule.decorate(true, stats), isNull);
    });
  });

  group('composition', () {
    final stats = computeColumnStats([0, 100]);

    test('FirstMatchRule takes the first that fires', () {
      const rule = FirstMatchRule([
        ThresholdRule(threshold: 90),
        ColorScaleRule(),
      ]);
      expect(rule.decorate(95, stats)!.bar, isNull);
      expect(rule.decorate(10, stats)!.tone, CellTone.positive);
    });

    test('FirstMatchRule falls through to nothing', () {
      const rule = FirstMatchRule([ThresholdRule(threshold: 1000)]);
      expect(rule.decorate(5, stats), isNull);
    });

    test('MergedRule combines a bar with a tone', () {
      const rule = MergedRule([
        DataBarRule(),
        ThresholdRule(threshold: 90, bold: true),
      ]);
      final high = rule.decorate(95, stats)!;
      expect(high.bar, closeTo(0.95, 0.0001));
      expect(high.tone, CellTone.severe);
      expect(high.bold, isTrue);

      final low = rule.decorate(10, stats)!;
      expect(low.bar, closeTo(0.1, 0.0001));
      expect(low.tone, CellTone.info);
      expect(low.bold, isFalse);
    });
  });

  group('through the controller', () {
    GridController<Product> gridWithRules() {
      final columns = productColumns();
      columns[2] = columns[2].copyWith(rule: const DataBarRule());
      columns[1] = columns[1].copyWith(
        rule: const ValueToneRule({'Compute': CellTone.severe}),
      );
      return GridController<Product>(
        columns: columns,
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
      );
    }

    test('stats cover the matched rows', () {
      final grid = gridWithRules();
      expect(grid.statsFor('price').min, 25);
      expect(grid.statsFor('price').max, 1450);
    });

    test('stats follow the filter, so bars rescale to what is shown', () {
      final grid = gridWithRules();
      grid.setSearch('Input');
      expect(grid.statsFor('price').max, 80);
      grid.setSearch('');
      expect(grid.statsFor('price').max, 1450);
    });

    test('stats follow a mutation', () {
      final grid = gridWithRules();
      expect(grid.statsFor('price').max, 1450);
      (grid.dataSource as InMemoryDataSource<Product>).add(
        Product(id: 9, name: 'Rack', category: 'Compute', price: 9000),
      );
      expect(grid.statsFor('price').max, 9000);
    });

    test('decorationFor applies the column rule', () {
      final grid = gridWithRules();
      // Measured from the column minimum, so the cheapest row has no bar at
      // all and the dearest fills it.
      expect(grid.decorationFor('price', grid.dataAt(1)!).bar, 0);
      expect(grid.decorationFor('price', grid.dataAt(3)!).bar, 1);
      expect(
        grid.decorationFor('price', grid.dataAt(4)!).bar,
        closeTo((180 - 25) / (1450 - 25), 0.0001),
      );
    });

    test('a column without a rule is undecorated, not null', () {
      final grid = gridWithRules();
      final decoration = grid.decorationFor('name', grid.dataAt(0)!);
      expect(decoration, CellDecoration.none);
      expect(decoration.isEmpty, isTrue);
    });

    test('a tone rule reads discrete values', () {
      final grid = gridWithRules();
      expect(
        grid.decorationFor('category', grid.dataAt(3)!).tone,
        CellTone.severe,
      );
      expect(
        grid.decorationFor('category', grid.dataAt(0)!).tone,
        CellTone.neutral,
      );
    });

    test('an unknown field decorates nothing rather than throwing', () {
      final grid = gridWithRules();
      expect(grid.decorationFor('nope', grid.dataAt(0)!), CellDecoration.none);
    });
  });
}
