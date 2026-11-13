import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  List<String> lines(String csv) =>
      csv.split('\r\n').where((l) => l.isNotEmpty).toList();

  group('CsvExporter', () {
    test('writes a header then one line per row, CRLF terminated', () {
      final csv = CsvExporter(productColumns()).exportRows(sampleProducts());
      expect(csv.endsWith('\r\n'), isTrue);
      final rows = lines(csv);
      expect(rows.length, 7);
      expect(rows.first, 'Name,Category,Price,Stock,Active');
      expect(rows[1], 'Keyboard,Input,80.00 USD,12,true');
    });

    test('omits the header when asked', () {
      final csv = CsvExporter(
        productColumns(),
        options: const ExportOptions(includeHeader: false),
      ).exportRows(sampleProducts());
      expect(lines(csv).length, 6);
    });

    test('exports formatted text by default and raw values on request', () {
      expect(
        lines(CsvExporter(productColumns()).exportRows(sampleProducts()))[1],
        contains('80.00 USD'),
      );
      expect(
        lines(
          CsvExporter(
            productColumns(),
            options: const ExportOptions(formatted: false),
          ).exportRows(sampleProducts()),
        )[1],
        contains(',80,'),
      );
    });

    test('exports only the requested fields, in the order given', () {
      final csv = CsvExporter(
        productColumns(),
        options: const ExportOptions(fields: ['price', 'name']),
      ).exportRows(sampleProducts());
      expect(lines(csv).first, 'Price,Name');
      expect(lines(csv)[1], '80.00 USD,Keyboard');
    });

    test('skips hidden columns', () {
      final columns = productColumns()
        ..[1] = productColumns()[1].copyWith(visible: false);
      expect(
        lines(CsvExporter(columns).exportRows(sampleProducts())).first,
        'Name,Price,Stock,Active',
      );
    });

    test('writes an empty cell for a null value', () {
      final csv = CsvExporter(productColumns()).exportRows([
        Product(id: 1, name: 'Laptop', category: 'Compute', price: 10),
      ]);
      expect(lines(csv)[1], 'Laptop,Compute,10.00 USD,,true');
    });

    test('honours a custom delimiter and line ending', () {
      final csv = CsvExporter(
        productColumns(),
        options: const ExportOptions(delimiter: ';', lineEnding: '\n'),
      ).exportRows([
        Product(id: 1, name: 'Mouse', category: 'Input', price: 25, stock: 1),
      ]);
      expect(csv.split('\n')[1], 'Mouse;Input;25.00 USD;1;true');
    });
  });

  group('RFC 4180 quoting', () {
    String cellFor(String name, {String delimiter = ','}) {
      final csv = CsvExporter(
        [GridColumn<Product>(field: 'name', value: (p) => p.name)],
        options: ExportOptions(includeHeader: false, delimiter: delimiter),
      ).exportRows([
        Product(id: 1, name: name, category: 'x', price: 0),
      ]);
      return csv.trimRight();
    }

    test('quotes a value containing the delimiter', () {
      expect(cellFor('Mouse, wireless'), '"Mouse, wireless"');
    });

    test('quotes and doubles embedded quotes', () {
      expect(cellFor('24" Monitor'), '"24"" Monitor"');
    });

    test('quotes a value containing a newline', () {
      expect(cellFor('line one\nline two'), '"line one\nline two"');
    });

    test('leaves a plain value unquoted', () {
      expect(cellFor('Keyboard'), 'Keyboard');
    });

    test('quotes against a custom delimiter, not the comma', () {
      expect(cellFor('a,b', delimiter: ';'), 'a,b');
      expect(cellFor('a;b', delimiter: ';'), '"a;b"');
    });
  });

  group('grouped export', () {
    List<GroupNode<Product>> groups() => buildGroups(
          sampleProducts(),
          [const GroupSpec('category')],
          productColumnMap(),
        );

    test('writes an indented header line with the group count', () {
      final csv = CsvExporter(productColumns())
          .exportGroups(groups(), GroupExpansionState());
      final rows = lines(csv);
      expect(rows[1], startsWith('Compute (2)'));
      expect(rows[2], startsWith('    Laptop'));
    });

    test('group headers can be left out entirely', () {
      final csv = CsvExporter(
        productColumns(),
        options: const ExportOptions(includeGroupRows: false),
      ).exportGroups(groups(), GroupExpansionState());
      expect(lines(csv).length, 7);
    });

    test('nested groups indent by depth', () {
      final nested = buildGroups(
        sampleProducts(),
        [const GroupSpec('category'), const GroupSpec('active')],
        productColumnMap(),
      );
      final rows = lines(
        CsvExporter(productColumns())
            .exportGroups(nested, GroupExpansionState()),
      );
      expect(rows[1], startsWith('Compute (2)'));
      expect(rows[2], startsWith('    false (1)'));
      expect(rows[3], startsWith('        Dock'));
    });

    test('exportResult picks the shape the result carries', () {
      final flat = GridResult<Product>(rows: sampleProducts(), totalCount: 6);
      final grouped = GridResult<Product>(
        rows: const [],
        groups: groups(),
        totalCount: 6,
      );
      final exporter = CsvExporter(productColumns());
      expect(
        lines(exporter.exportResult(flat, GroupExpansionState())).length,
        7,
      );
      expect(
        lines(exporter.exportResult(grouped, GroupExpansionState())).length,
        10,
      );
    });
  });

  test('toClipboardText joins cells with tabs and rows with newlines', () {
    expect(
      toClipboardText<Product>([
        ['a', 'b'],
        ['c', 'd'],
      ]),
      'a\tb\nc\td',
    );
  });
}
