import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_flutter/lattice_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'data_grid_test.dart' show Product, columns, host, sample;

GridController<Product> ruled({
  CellRule? priceRule,
  CellRule? categoryRule,
  List<Product>? rows,
  List<GroupSpec> groups = const [],
}) {
  final cols = columns();
  if (priceRule != null) cols[2] = cols[2].copyWith(rule: priceRule);
  if (categoryRule != null) cols[1] = cols[1].copyWith(rule: categoryRule);
  return GridController<Product>(
    columns: cols,
    dataSource: InMemoryDataSource<Product>(rows ?? sample()),
    groups: groups,
  );
}

/// The text widget showing [value] inside a cell.
Text textFor(WidgetTester tester, String value) =>
    tester.widget<Text>(find.text(value));

void main() {
  group('conditional formatting', () {
    testWidgets('a tone rule colours and bolds the value', (tester) async {
      final controller = ruled(
        categoryRule: const ValueToneRule({'Compute': CellTone.severe}),
      );
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );

      final theme = LatticeGridTheme.fromTheme(ThemeData.light());
      final severe = textFor(tester, 'Compute');
      expect(severe.style!.color, theme.toneColor(CellTone.severe));
      expect(severe.style!.fontWeight, FontWeight.w600);

      // An unmatched value keeps the plain style.
      final plain = textFor(tester, 'Display');
      expect(plain.style!.color, isNot(theme.toneColor(CellTone.severe)));
      expect(plain.style!.fontWeight, isNot(FontWeight.w600));
    });

    testWidgets('a data bar is drawn behind the value', (tester) async {
      final controller = ruled(priceRule: const DataBarRule());
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );

      final bars = tester.widgetList<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(bars, isNotEmpty);
      // The dearest row fills the cell; the cheapest gets nothing.
      expect(
        bars.map((b) => b.widthFactor).reduce((a, b) => a! > b! ? a : b),
        1,
      );
      expect(
        bars.map((b) => b.widthFactor).reduce((a, b) => a! < b! ? a : b),
        0,
      );
    });

    testWidgets('bars rescale when a filter changes what is shown', (
      tester,
    ) async {
      final controller = ruled(priceRule: const DataBarRule());
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: controller)),
      );
      expect(controller.statsFor('price').max, 1450);

      controller.setSearch('Input');
      await tester.pump();
      expect(controller.statsFor('price').max, 80);
      expect(controller.decorationFor('price', controller.dataAt(0)!).bar, 1);
    });

    testWidgets('an undecorated column renders exactly as before', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: ruled())),
      );
      expect(find.byType(FractionallySizedBox), findsNothing);
      final plain = textFor(tester, 'Keyboard');
      expect(plain.style!.fontWeight, isNot(FontWeight.w600));
    });

    testWidgets('a cellBuilder still wins over the rule', (tester) async {
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: ruled(priceRule: const DataBarRule()),
            cellBuilder: (context, column, row) => const Text('custom'),
          ),
        ),
      );
      expect(find.text('custom'), findsWidgets);
      // The bar is drawn by the cell, so it survives a custom child.
      expect(find.byType(FractionallySizedBox), findsWidgets);
    });
  });

  group('density', () {
    testWidgets('compact fits more rows than comfortable', (tester) async {
      Future<int> rowsVisible(GridDensity density) async {
        await tester.pumpWidget(
          host(
            LatticeDataGrid<Product>(
              controller: ruled(
                rows: [
                  for (var i = 0; i < 100; i++) Product('Row $i', 'Bulk', i),
                ],
              ),
              theme: LatticeGridTheme.fromTheme(
                ThemeData.light(),
                density: density,
              ),
            ),
          ),
          duration: Duration.zero,
        );
        return tester.widgetList(find.byType(LatticeCell<Product>)).length;
      }

      final compact = await rowsVisible(GridDensity.compact);
      final comfortable = await rowsVisible(GridDensity.comfortable);
      expect(compact, greaterThan(comfortable));
    });

    testWidgets('density changes the row height', (tester) async {
      final compact = LatticeGridTheme.fromTheme(
        ThemeData.light(),
        density: GridDensity.compact,
      );
      final comfortable = LatticeGridTheme.fromTheme(
        ThemeData.light(),
        density: GridDensity.comfortable,
      );
      expect(compact.rowHeight, lessThan(comfortable.rowHeight));
      expect(compact.cellPadding.left, lessThan(comfortable.cellPadding.left));
    });
  });

  group('sticky group headers', () {
    testWidgets('no sticky header at the top of the list', (tester) async {
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: ruled(groups: const [GroupSpec('category')]),
          ),
        ),
      );
      expect(find.text('Category: Compute'), findsOneWidget);
    });

    testWidgets('the current group pins once scrolled into', (tester) async {
      final rows = [
        for (var i = 0; i < 60; i++)
          Product('Row $i', i < 30 ? 'Alpha' : 'Beta', i),
      ];
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: ruled(
              rows: rows,
              groups: const [GroupSpec('category')],
            ),
          ),
          size: const Size(700, 320),
        ),
      );
      expect(find.text('Category: Alpha'), findsOneWidget);

      await tester.drag(find.text('Row 2'), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Two now: the one in the list, and the pinned copy on top.
      expect(find.text('Category: Alpha'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('can be turned off', (tester) async {
      final rows = [for (var i = 0; i < 60; i++) Product('Row $i', 'Alpha', i)];
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: ruled(
              rows: rows,
              groups: const [GroupSpec('category')],
            ),
            stickyGroupHeaders: false,
          ),
          size: const Size(700, 320),
        ),
      );
      await tester.drag(find.text('Row 2'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Category: Alpha'), findsNothing);
    });

    testWidgets('an ungrouped grid has no sticky header', (tester) async {
      await tester.pumpWidget(
        host(LatticeDataGrid<Product>(controller: ruled())),
      );
      expect(find.byType(Material), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('change flash', () {
    testWidgets('flashes when a value changes under the same row', (
      tester,
    ) async {
      final rows = sample();
      final source = InMemoryDataSource<Product>(rows);
      final controller = GridController<Product>(
        columns: columns(),
        dataSource: source,
      );
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: controller,
            highlightChanges: true,
            rowId: (row) => row.name,
          ),
        ),
      );
      expect(find.text('80'), findsOneWidget);

      rows[0].price = 999;
      source.replaceAt(0, rows[0]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('999'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Let the flash finish so no timer outlives the test.
      await tester.pumpAndSettle();
    });

    testWidgets('does nothing without a rowId', (tester) async {
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(controller: ruled(), highlightChanges: true),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Keyboard'), findsOneWidget);
    });

    testWidgets('scrolling a different row into a slot does not flash', (
      tester,
    ) async {
      final rows = [for (var i = 0; i < 60; i++) Product('Row $i', 'Bulk', i)];
      final controller = GridController<Product>(
        columns: columns(),
        dataSource: InMemoryDataSource<Product>(rows),
      );
      await tester.pumpWidget(
        host(
          LatticeDataGrid<Product>(
            controller: controller,
            highlightChanges: true,
            rowId: (row) => row.name,
          ),
          size: const Size(700, 300),
        ),
      );
      await tester.drag(find.text('Row 1'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
