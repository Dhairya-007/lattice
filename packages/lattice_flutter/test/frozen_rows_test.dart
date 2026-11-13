import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_flutter/lattice_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'data_grid_test.dart' show Product, columns, host;

List<Product> many([int count = 60]) => [
  for (var i = 0; i < count; i++) Product('Row $i', 'Bulk', i),
];

GridController<Product> frozen({
  int top = 0,
  int bottom = 0,
  List<Product>? rows,
  List<GridColumn<Product>>? cols,
}) {
  return GridController<Product>(
    columns: cols ?? columns(),
    dataSource: InMemoryDataSource<Product>(rows ?? many()),
    frozenRowCount: top,
    frozenRowCountBottom: bottom,
  );
}

void main() {
  testWidgets('a pinned row stays while the rest scrolls', (tester) async {
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: frozen(top: 2)),
        size: const Size(700, 320),
      ),
    );
    expect(find.text('Row 0'), findsOneWidget);
    expect(find.text('Row 1'), findsOneWidget);

    await tester.drag(find.text('Row 5'), const Offset(0, -600));
    await tester.pumpAndSettle();

    // The pinned rows are still there; the rows below them have moved on.
    expect(find.text('Row 0'), findsOneWidget);
    expect(find.text('Row 1'), findsOneWidget);
    expect(find.text('Row 5'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bottom band pins the last rows', (tester) async {
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: frozen(bottom: 1)),
        size: const Size(700, 320),
      ),
    );
    // The last row is visible without scrolling at all.
    expect(find.text('Row 59'), findsOneWidget);
    expect(find.text('Row 30'), findsNothing);
  });

  testWidgets('both bands can be pinned at once', (tester) async {
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: frozen(top: 1, bottom: 1)),
        size: const Size(700, 320),
      ),
    );
    final first = tester.getRect(find.text('Row 0'));
    final last = tester.getRect(find.text('Row 59'));
    expect(first.top, lessThan(last.top));
    expect(find.text('Row 1'), findsOneWidget);
  });

  testWidgets('a pinned row is drawn once, not twice', (tester) async {
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: frozen(top: 2)),
        size: const Size(700, 320),
      ),
    );
    expect(find.text('Row 0'), findsOneWidget);
    expect(find.text('Row 1'), findsOneWidget);
    expect(find.text('Row 2'), findsOneWidget);
  });

  testWidgets('pinned rows are still selectable', (tester) async {
    final controller = frozen(top: 1);
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: controller),
        size: const Size(700, 320),
      ),
    );
    await tester.tap(find.text('Row 0'));
    await tester.pump();
    expect(controller.selection.selectedRows, [0]);
  });

  testWidgets('pinning nothing renders exactly as before', (tester) async {
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: frozen()),
        size: const Size(700, 320),
      ),
    );
    expect(find.text('Row 0'), findsOneWidget);
    await tester.drag(find.text('Row 2'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsNothing);
  });

  testWidgets('changing the count at runtime repins', (tester) async {
    final controller = frozen();
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: controller),
        size: const Size(700, 320),
      ),
    );
    controller.frozenRowCount = 1;
    await tester.pumpAndSettle();

    await tester.drag(find.text('Row 4'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsOneWidget);
  });

  testWidgets('frozen rows work with a frozen column', (tester) async {
    final cols = columns();
    cols[0] = cols[0].copyWith(pin: ColumnPin.start);
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: frozen(top: 1, cols: cols)),
        size: const Size(500, 320),
      ),
    );
    expect(find.text('Row 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a grid too short to freeze still scrolls', (tester) async {
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: frozen(top: 5, rows: many(2))),
        size: const Size(700, 320),
      ),
    );
    expect(find.text('Row 0'), findsOneWidget);
    expect(find.text('Row 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
