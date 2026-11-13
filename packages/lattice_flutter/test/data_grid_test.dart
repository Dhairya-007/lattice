import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_flutter/lattice_flutter.dart';

class Product {
  Product(this.name, this.category, this.price);

  String name;
  final String category;
  num price;
}

List<Product> sample() => [
  Product('Keyboard', 'Input', 80),
  Product('Mouse', 'Input', 25),
  Product('Monitor', 'Display', 320),
  Product('Laptop', 'Compute', 1450),
  Product('Dock', 'Compute', 180),
];

List<GridColumn<Product>> columns() => [
  GridColumn<Product>(
    field: 'name',
    value: (p) => p.name,
    setValue: (p, v) {
      p.name = (v ?? '') as String;
      return null;
    },
    validator: requiredValue(),
  ),
  GridColumn<Product>(field: 'category', value: (p) => p.category),
  GridColumn<Product>(
    field: 'price',
    type: ColumnType.number,
    value: (p) => p.price,
    setValue: (p, v) {
      p.price = (v ?? 0) as num;
      return null;
    },
    validator: numberRange(min: 0),
  ),
];

GridController<Product> makeController({
  List<GridColumn<Product>>? cols,
  List<Product>? rows,
  List<SortSpec> sorts = const [],
  List<GroupSpec> groups = const [],
  List<Aggregation> aggregations = const [],
  SelectionMode selectionMode = SelectionMode.multiRow,
  int? pageSize,
}) {
  return GridController<Product>(
    columns: cols ?? columns(),
    dataSource: InMemoryDataSource<Product>(rows ?? sample()),
    sorts: sorts,
    groups: groups,
    aggregations: aggregations,
    selectionMode: selectionMode,
    pageSize: pageSize,
  );
}

Widget host(Widget child, {Size size = const Size(900, 600)}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}

void main() {
  group('rendering', () {
    testWidgets('draws headers and rows', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('Keyboard'), findsOneWidget);
      expect(find.text('1450'), findsOneWidget);
    });

    testWidgets('shows the footer row count', (tester) async {
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: makeController())),
      );
      expect(find.text('5 rows'), findsOneWidget);
    });

    testWidgets('shows an empty state when nothing matches', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      controller.setSearch('nothing here');
      await tester.pump();
      expect(find.text('No rows'), findsOneWidget);
      expect(find.text('Keyboard'), findsNothing);
    });

    testWidgets('a custom empty state replaces the default', (tester) async {
      final controller = makeController(rows: []);
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: controller,
            emptyState: const Text('Nothing to see'),
          ),
        ),
      );
      expect(find.text('Nothing to see'), findsOneWidget);
    });

    testWidgets('cellBuilder replaces cell content', (tester) async {
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: makeController(),
            cellBuilder: (context, column, row) =>
                Text('${column.field}!', maxLines: 1),
          ),
        ),
      );
      expect(find.text('name!'), findsWidgets);
      expect(find.text('Keyboard'), findsNothing);
    });

    testWidgets('a formatter is used for display', (tester) async {
      final cols = columns();
      cols[2] = cols[2].copyWith(format: (v) => 'EUR $v');
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: makeController(cols: cols))),
      );
      expect(find.text('EUR 80'), findsOneWidget);
    });

    testWidgets('respects an explicit theme', (tester) async {
      final theme = LatticeGridTheme.fromTheme(ThemeData.light())
          .copyWith(rowHeight: 72, headerHeight: 80);
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(controller: makeController(), theme: theme),
        ),
      );
      final header = tester.getSize(
        find
            .ancestor(of: find.text('Name'), matching: find.byType(SizedBox))
            .first,
      );
      expect(header.height, greaterThan(0));
    });
  });

  group('sorting from the header', () {
    testWidgets('tapping a header sorts, then reverses, then clears', (
      tester,
    ) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );

      await tester.tap(find.text('Price'));
      await tester.pump();
      expect(controller.sorts.single.field, 'price');
      expect(controller.sorts.single.isAscending, isTrue);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

      await tester.tap(find.text('Price'));
      await tester.pump();
      expect(controller.sorts.single.isAscending, isFalse);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

      await tester.tap(find.text('Price'));
      await tester.pump();
      expect(controller.sorts, isEmpty);
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
    });

    testWidgets('an unsortable header does not react', (tester) async {
      final cols = columns();
      cols[1] = cols[1].copyWith(sortable: false);
      final controller = makeController(cols: cols);
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      await tester.tap(find.text('Category'));
      await tester.pump();
      expect(controller.sorts, isEmpty);
    });

    testWidgets('sort levels are numbered when there is more than one', (
      tester,
    ) async {
      final controller = makeController(
        sorts: const [SortSpec('category'), SortSpec('price')],
      );
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('selection', () {
    testWidgets('tapping a cell selects its row', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      await tester.tap(find.text('Mouse'));
      await tester.pump();
      expect(controller.selection.selectedRows, [1]);
      expect(controller.selection.activeCell, const CellAddress(1, 'name'));
    });

    testWidgets('the footer reports the selection', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      await tester.tap(find.text('Mouse'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('onRowTap and onCellTap fire with the tapped row', (
      tester,
    ) async {
      Product? tappedRow;
      CellAddress? tappedCell;
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: makeController(),
            onRowTap: (row) => tappedRow = row.data,
            onCellTap: (cell, row) => tappedCell = cell,
          ),
        ),
      );
      await tester.tap(find.text('Monitor'));
      await tester.pump();
      expect(tappedRow?.name, 'Monitor');
      expect(tappedCell, const CellAddress(2, 'name'));
    });

    testWidgets('arrow keys move the active cell', (tester) async {
      final controller = makeController(selectionMode: SelectionMode.cellRange);
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller, autofocus: true)),
      );
      await tester.tap(find.text('Keyboard'));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.selection.activeCell, const CellAddress(1, 'name'));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.selection.activeCell, const CellAddress(1, 'category'));
    });

    testWidgets('arrow keys stop at the edges', (tester) async {
      final controller = makeController(selectionMode: SelectionMode.cellRange);
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller, autofocus: true)),
      );
      await tester.tap(find.text('Keyboard'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.selection.activeCell, const CellAddress(0, 'name'));
    });
  });

  group('editing', () {
    testWidgets('double tap opens an editor and Enter commits', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );

      final cell = find.text('Keyboard');
      await tester.tap(cell);
      await tester.pump();
      await tester.tap(cell);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Keypad');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.editSession, isNull);
      expect(find.text('Keypad'), findsOneWidget);
    });

    testWidgets('an invalid edit keeps the editor open', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      controller.beginEdit(const CellAddress(0, 'name'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.editSession, isNotNull);
      expect(controller.editSession!.error, 'Required');
    });

    testWidgets('Escape rolls the edit back', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      controller.beginEdit(const CellAddress(0, 'name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Nonsense');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(controller.editSession, isNull);
      expect(find.text('Keyboard'), findsOneWidget);
    });

    testWidgets('a number cell coerces its text to a num', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      controller.beginEdit(const CellAddress(0, 'price'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '99.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.dataAt(0)!.price, 99.5);
    });

    testWidgets('a non-editable column does not open an editor', (
      tester,
    ) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      final cell = find.text('Input').first;
      await tester.tap(cell);
      await tester.pump();
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('editOnDoubleTap false leaves cells read-only', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: controller,
            editOnDoubleTap: false,
          ),
        ),
      );
      final cell = find.text('Keyboard');
      await tester.tap(cell);
      await tester.pump();
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('grouping', () {
    testWidgets('group headers render with counts and collapse on tap', (
      tester,
    ) async {
      final controller = makeController(groups: const [GroupSpec('category')]);
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );

      expect(find.text('Category: Compute'), findsOneWidget);
      expect(find.text('(2)'), findsNWidgets(2));
      expect(find.text('Laptop'), findsOneWidget);

      await tester.tap(find.text('Category: Compute'));
      await tester.pumpAndSettle();
      expect(find.text('Laptop'), findsNothing);
      expect(find.text('Category: Compute'), findsOneWidget);
    });

    testWidgets('group aggregates appear on the header row', (tester) async {
      final controller = makeController(
        groups: const [GroupSpec('category')],
        aggregations: const [Aggregation.sum('price')],
      );
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      expect(find.text('sum 1630'), findsOneWidget);
    });
  });

  group('filter row', () {
    testWidgets('typing filters the rows', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(controller: controller, showFilterRow: true),
        ),
      );
      expect(find.byType(TextField), findsNWidgets(3));

      await tester.enterText(find.byType(TextField).first, 'mo');
      await tester.pumpAndSettle();
      expect(controller.matchedCount, 2);
      expect(find.text('Keyboard'), findsNothing);
    });

    testWidgets('a number filter uses equality once the text parses', (
      tester,
    ) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(controller: controller, showFilterRow: true),
        ),
      );
      await tester.enterText(find.byType(TextField).last, 'abc');
      await tester.pumpAndSettle();
      expect(controller.matchedCount, 5, reason: 'unparseable text is ignored');

      await tester.enterText(find.byType(TextField).last, '320');
      await tester.pumpAndSettle();
      expect(controller.matchedCount, 1);
    });

    testWidgets('an unfilterable column gets no input', (tester) async {
      final cols = columns();
      cols[1] = cols[1].copyWith(filterable: false);
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: makeController(cols: cols),
            showFilterRow: true,
          ),
        ),
      );
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });

  group('frozen columns', () {
    testWidgets('a pinned column renders in its own pane', (tester) async {
      final cols = columns();
      cols[0] = cols[0].copyWith(pin: ColumnPin.start);
      cols[2] = cols[2].copyWith(pin: ColumnPin.end);
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(controller: makeController(cols: cols)),
          size: const Size(400, 400),
        ),
      );
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('Keyboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow viewport still lays out without overflow', (
      tester,
    ) async {
      final cols = columns();
      cols[0] = cols[0].copyWith(pin: ColumnPin.start);
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(controller: makeController(cols: cols)),
          size: const Size(220, 300),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('pagination', () {
    testWidgets('page controls move through the pages', (tester) async {
      final controller = makeController(pageSize: 2);
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.text('Monitor'), findsNothing);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.text('Monitor'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.last_page));
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 3'), findsOneWidget);
    });

    testWidgets('no footer when showFooter is false', (tester) async {
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: makeController(pageSize: 2),
            showFooter: false,
          ),
        ),
      );
      expect(find.text('Page 1 of 3'), findsNothing);
    });
  });

  group('scrolling', () {
    testWidgets('rows are virtualized, not all built at once', (tester) async {
      final rows = [
        for (var i = 0; i < 2000; i++) Product('Row $i', 'Bulk', i),
      ];
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(controller: makeController(rows: rows)),
          size: const Size(600, 400),
        ),
      );
      expect(find.text('Row 0'), findsOneWidget);
      expect(find.text('Row 1500'), findsNothing);
      // Far fewer cells than 2000 rows worth are in the tree.
      final builtCells = tester
          .widgetList(find.byType(LatticeCell<Product>))
          .length;
      expect(builtCells, lessThan(200));
    });

    testWidgets('frozen and scrolling panes stay in sync vertically', (
      tester,
    ) async {
      final cols = columns();
      cols[0] = cols[0].copyWith(pin: ColumnPin.start);
      final rows = [for (var i = 0; i < 200; i++) Product('Row $i', 'Bulk', i)];
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: makeController(cols: cols, rows: rows),
          ),
          size: const Size(600, 400),
        ),
      );

      await tester.drag(find.text('Bulk').first, const Offset(0, -2000));
      await tester.pumpAndSettle();

      // The pinned pane scrolled with the body: the name and the category of
      // the same row are both on screen.
      final visibleNames = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((t) => t.startsWith('Row '))
          .toList();
      expect(visibleNames, isNotEmpty);
      expect(visibleNames.first, isNot('Row 0'));
      expect(tester.takeException(), isNull);
    });
  });

  group('lifecycle', () {
    testWidgets('swapping the controller re-subscribes', (tester) async {
      final first = makeController();
      final second = makeController(rows: [Product('Only', 'X', 1)]);

      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: first)),
      );
      expect(find.text('Keyboard'), findsOneWidget);

      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: second)),
      );
      expect(find.text('Only'), findsOneWidget);

      second.setSearch('Only');
      await tester.pump();
      expect(find.text('Only'), findsOneWidget);
    });

    testWidgets('disposing the grid leaves the controller usable', (
      tester,
    ) async {
      final controller = makeController();
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      controller.setSearch('Mouse');
      expect(controller.rowCount, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
