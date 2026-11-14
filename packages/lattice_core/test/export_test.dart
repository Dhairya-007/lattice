// The pipeline stages this exercises are the engine's inner layer.
import 'package:lattice_core/advanced.dart';
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

  group('formula injection', () {
    String cellFor(String name, {bool sanitize = true}) {
      final csv = CsvExporter(
        [GridColumn<Product>(field: 'name', value: (p) => p.name)],
        options: ExportOptions(
          includeHeader: false,
          sanitizeFormulas: sanitize,
        ),
      ).exportRows([Product(id: 1, name: name, category: 'x', price: 0)]);
      return csv.trimRight();
    }

    test('recognises every character a spreadsheet executes', () {
      for (final start in ['=', '+', '-', '@', '\t', '\r']) {
        expect(
          CsvExporter.isFormula('${start}cmd'),
          isTrue,
          reason: 'should treat a leading "$start" as a formula',
        );
      }
      expect(CsvExporter.isFormula('Keyboard'), isFalse);
      expect(CsvExporter.isFormula(''), isFalse);
    });

    test('neutralises a formula by default', () {
      expect(cellFor('=1+1'), "'=1+1");
      expect(cellFor('@SUM(A1)'), "'@SUM(A1)");
    });

    test('neutralises the attack that fetches a remote payload', () {
      // The canonical CSV injection: a cell that runs a command on open.
      const attack = '=cmd|\' /C calc\'!A0';
      final exported = cellFor(attack);
      expect(exported.startsWith("'"), isTrue);
      expect(exported.startsWith('='), isFalse);
    });

    test('puts the prefix inside the quotes, not outside them', () {
      // Outside, a reader would strip it with the quotes and run the formula.
      final exported = cellFor('=A1,B1');
      expect(exported, startsWith('"\''));
      expect(exported, endsWith('"'));
    });

    test('leaves ordinary values untouched', () {
      expect(cellFor('Keyboard'), 'Keyboard');
      expect(cellFor('12.50 USD'), '12.50 USD');
      expect(cellFor('a=b'), 'a=b');
    });

    test('a negative number is quoted as text, which is the trade-off', () {
      // '-5' is indistinguishable from the start of a formula, so it is
      // sanitised too. Machine-read exports should turn this off.
      expect(cellFor('-5'), "'-5");
      expect(cellFor('-5', sanitize: false), '-5');
    });

    test('can be turned off for a machine-read export', () {
      expect(cellFor('=1+1', sanitize: false), '=1+1');
    });

    test('a custom prefix is honoured', () {
      final csv = CsvExporter(
        [GridColumn<Product>(field: 'name', value: (p) => p.name)],
        options: const ExportOptions(
          includeHeader: false,
          formulaPrefix: '_',
        ),
      ).exportRows([Product(id: 1, name: '=1+1', category: 'x', price: 0)]);
      expect(csv.trimRight(), '_=1+1');
    });

    test('leading spaces do not hide a formula', () {
      // Spreadsheets trim them on import, and a grouped export indents its
      // rows, so the check has to look past them.
      expect(CsvExporter.isFormula('   =cmd'), isTrue);
      expect(CsvExporter.isFormula('   safe'), isFalse);
      expect(cellFor('   =cmd'), "'   =cmd");
    });

    test('group labels and headers go through the same guard', () {
      final columns = [
        GridColumn<Product>(field: 'name', value: (p) => p.name),
        GridColumn<Product>(field: 'category', value: (p) => p.category),
      ];
      final groups = buildGroups(
        [Product(id: 1, name: '=evil()', category: 'Input', price: 1)],
        [const GroupSpec('category')],
        {for (final c in columns) c.field: c},
      );
      final csv = CsvExporter(
        columns,
      ).exportGroups(groups, GroupExpansionState());
      // The prefix lands ahead of the indent, so the apostrophe is the
      // first character the spreadsheet sees.
      expect(csv, contains("'    =evil()"));
      for (final line in csv.split('\r\n')) {
        expect(CsvExporter.isFormula(line), isFalse);
      }
    });

    test('clipboard text is sanitised too', () {
      expect(
        toClipboardText<Product>([
          ['=1+1', 'safe'],
        ]),
        "'=1+1\tsafe",
      );
      expect(
        toClipboardText<Product>([
          ['=1+1'],
        ], sanitizeFormulas: false),
        '=1+1',
      );
    });
  });

  group('export matches the screen', () {
    test('columns are written in screen order, pinning included', () {
      final grid = productGrid();
      grid.setColumnPin('price', ColumnPin.start);
      final header = grid.exportCsv().split('\r\n').first;
      expect(header, 'Price,Name,Category,Stock,Active');
    });

    test('an explicit field list still wins over screen order', () {
      final grid = productGrid();
      grid.setColumnPin('price', ColumnPin.start);
      final header = grid
          .exportCsv(options: const ExportOptions(fields: ['name', 'price']))
          .split('\r\n')
          .first;
      expect(header, 'Name,Price');
    });

    test('a copied range covers the columns that are next to each other', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      grid.setColumnPin('stock', ColumnPin.start);
      grid.selectCell(const CellAddress(0, 'stock'));
      grid.extendSelectionTo(const CellAddress(0, 'name'));
      expect(grid.copySelectionAsText(), '12\tKeyboard');
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
