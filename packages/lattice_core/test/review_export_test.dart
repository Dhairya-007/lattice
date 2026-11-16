// Export, clipboard, aggregate and coercion fixes from the 0.4.0 review.
import 'package:lattice_core/advanced.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

GridController<Product> groupedGrid() => GridController<Product>(
      columns: productColumns(),
      dataSource: InMemoryDataSource<Product>(sampleProducts()),
      groups: const [GroupSpec('category')],
    );

void main() {
  group('grouped export', () {
    test('indents the first cell only, so numbers stay numbers', () {
      final grid = groupedGrid();
      final csv = grid.exportCsv();
      final lines = csv.trim().split('\r\n');
      final dataLine = lines.firstWhere((l) => l.contains('Laptop'));
      expect(dataLine, startsWith('    Laptop,'));
      expect(dataLine, contains(',1450.00 USD'));
      expect(dataLine, isNot(contains('"    1450')));
      grid.dispose();
    });

    test('leaves out a collapsed group, as the screen does', () {
      final grid = groupedGrid();
      final all = grid.exportCsv();
      expect(all, contains('Laptop'));

      grid.collapseAllGroups();
      final collapsed = grid.exportCsv();
      expect(collapsed, contains('Compute'));
      expect(collapsed, isNot(contains('Laptop')));

      final regardless = grid.exportCsv(
        options: const ExportOptions(respectCollapsed: false),
      );
      expect(regardless, contains('Laptop'));
      grid.dispose();
    });

    test('an export with no columns is empty, not an error', () {
      final grid = groupedGrid();
      expect(
        () => grid.exportCsv(options: const ExportOptions(fields: [])),
        returnsNormally,
      );
      expect(grid.exportCsv(options: const ExportOptions(fields: [])), '');
      grid.dispose();
    });

    test('a single-column export writes one cell per group header', () {
      final grid = groupedGrid();
      final csv = grid.exportCsv(
        options: const ExportOptions(fields: ['name']),
      );
      expect(csv, contains('Compute (2)'));
      grid.dispose();
    });
  });

  group('a numeric column', () {
    test('exports a negative number as a number', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>([
          Product(id: 1, name: 'Refund', category: 'c', price: -5),
        ]),
      );
      final csv = grid.exportCsv(
        options: const ExportOptions(formatted: false),
      );
      expect(csv, contains(',-5,'));
      expect(csv, isNot(contains("'-5")));
      grid.dispose();
    });
  });

  group('the clipboard', () {
    test('round-trips a cell holding a line break', () {
      const cells = [
        ['line1\nline2', 'b'],
        ['c', 'd'],
      ];
      final text = toClipboardText<Product>(cells);
      expect(parseClipboardText(text), cells);
      expect(parseClipboardText(text), hasLength(2));
    });

    test('round-trips a cell holding a tab and a quote', () {
      const cells = [
        ['a\tb', 'say "hi"'],
      ];
      expect(parseClipboardText(toClipboardText<Product>(cells)), cells);
    });

    test('reads the quoted text a spreadsheet produces', () {
      expect(
        parseClipboardText('"one\ttwo"\tthree'),
        [
          ['one\ttwo', 'three'],
        ],
      );
    });

    test('copying across a group header writes its label, not a blank row', () {
      final grid = groupedGrid();
      final header = grid.visibleRows.whereType<GroupGridRow<Product>>().first;
      grid.selection.selectRow(header.index);
      grid.selection.selectRow(header.index + 1, SelectionModifiers.toggling);
      final lines = grid.copySelectionAsText().split('\n');
      expect(lines.first, startsWith('Compute (2)'));
      expect(lines.first.replaceAll('\t', ''), isNotEmpty);
      grid.dispose();
    });
  });

  group('pasting across a group header', () {
    test('fills the next data row instead of dropping one', () {
      final products = sampleProducts();
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(products),
        groups: const [GroupSpec('category')],
        rowKey: (p) => p.id,
      );
      // The first data row of the first group.
      final firstData =
          grid.visibleRows.whereType<DataGridRow<Product>>().first;
      final names = [
        for (final r in grid.visibleRows.whereType<DataGridRow<Product>>())
          r.data.name,
      ];
      final result = grid.pasteText(
        'A\nB\nC',
        at: CellAddress(firstData.index, 'name'),
      );
      expect(result.rowsChanged, 3, reason: 'no row is lost to a header');
      final after = [
        for (final r in grid.visibleRows.whereType<DataGridRow<Product>>())
          r.data.name,
      ];
      expect(after.where((n) => ['A', 'B', 'C'].contains(n)), hasLength(3));
      expect(after, isNot(names));
      grid.dispose();
    });
  });

  group('aggregates', () {
    test('countDistinct does not count null as a value', () {
      const count = Aggregation('f', type: AggregateType.countDistinct);
      expect(count.apply(['a', 'b', null, 'a']), 2);
    });

    test('sum and average ignore text that parses as NaN', () {
      const sum = Aggregation('f', type: AggregateType.sum);
      const average = Aggregation('f', type: AggregateType.average);
      expect(sum.apply([1, 'NaN', 2]), 3);
      expect(sum.apply([1, 'Infinity']), 1);
      expect(average.apply([1, 'NaN', 3]), 2);
      expect(sum.apply([double.nan]), isNull);
    });

    test('a tiny negative average does not format as minus zero', () {
      const average = Aggregation('f', type: AggregateType.average);
      expect(average.formatted(-0.001), '0.00');
      expect(average.formatted(-0.02), '-0.02');
    });

    test('ColumnStats.mean divides by the numbers it added up', () {
      final stats = computeColumnStats(<Object?>[10, 'n/a']);
      expect(stats.count, 2);
      expect(stats.numberCount, 1);
      expect(stats.mean, 10);
    });
  });

  group('number coercion', () {
    test('accepts a decimal and refuses hex, NaN and infinity', () {
      expect(coerceValue('42', ColumnType.number), 42);
      expect(coerceValue('-3.5', ColumnType.number), -3.5);
      expect(coerceValue('1e3', ColumnType.number), 1000);
      expect(coerceValue('0x10', ColumnType.number), isNull);
      expect(coerceValue('NaN', ColumnType.number), isNull);
      expect(coerceValue('Infinity', ColumnType.number), isNull);
    });

    test('numberRange rejects a value that is not finite', () {
      final validator = numberRange(min: 0, max: 10);
      expect(validator(5), isNull);
      expect(validator(double.nan), isNotNull);
      expect(validator(double.infinity), isNotNull);
    });
  });
}
