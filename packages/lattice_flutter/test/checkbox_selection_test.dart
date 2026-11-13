import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_flutter/lattice_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'data_grid_test.dart' show Product, columns, host, sample;

GridController<Product> grid({List<Product>? rows}) {
  return GridController<Product>(
    columns: columns(),
    dataSource: InMemoryDataSource<Product>(rows ?? sample()),
  );
}

/// The header checkbox is the tri-state one.
Checkbox selectAllBox(WidgetTester tester) => tester
    .widgetList<Checkbox>(find.byType(Checkbox))
    .firstWhere((c) => c.tristate);

List<Checkbox> rowBoxes(WidgetTester tester) => tester
    .widgetList<Checkbox>(find.byType(Checkbox))
    .where((c) => !c.tristate)
    .toList();

void main() {
  testWidgets('no checkboxes unless asked for', (tester) async {
    await tester.pumpWidget(host(LatticeDataGrid<Product>(controller: grid())));
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('one checkbox per row plus the header', (tester) async {
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: grid(), showCheckboxColumn: true),
      ),
    );
    expect(rowBoxes(tester).length, 5);
    expect(selectAllBox(tester).value, isFalse);
  });

  testWidgets('ticking a row selects only that row', (tester) async {
    final controller = grid();
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: controller,
          showCheckboxColumn: true,
        ),
      ),
    );
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    expect(controller.selection.rowCount, 1);

    await tester.tap(find.byType(Checkbox).at(3));
    await tester.pumpAndSettle();
    expect(
      controller.selection.rowCount,
      2,
      reason: 'a checkbox adds to the selection rather than replacing it',
    );
  });

  testWidgets('the header goes dash, then ticked', (tester) async {
    final controller = grid();
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: controller,
          showCheckboxColumn: true,
        ),
      ),
    );
    controller.setRowSelected(0, true);
    await tester.pumpAndSettle();
    expect(selectAllBox(tester).value, isNull, reason: 'partial shows a dash');

    controller.selectAllRows();
    await tester.pumpAndSettle();
    expect(selectAllBox(tester).value, isTrue);
  });

  testWidgets('the header checkbox selects all, then clears', (tester) async {
    final controller = grid();
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: controller,
          showCheckboxColumn: true,
        ),
      ),
    );
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(controller.selection.rowCount, 5);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(controller.selection.isEmpty, isTrue);
  });

  testWidgets('checkboxes stay aligned with the rows they belong to', (
    tester,
  ) async {
    final controller = grid();
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: controller,
          showCheckboxColumn: true,
        ),
      ),
    );
    final boxRow = tester.getRect(find.byType(Checkbox).at(1));
    final textRow = tester.getRect(find.text('Keyboard'));
    expect(boxRow.center.dy, closeTo(textRow.center.dy, 2));
  });

  testWidgets('the column survives frozen rows and columns', (tester) async {
    final cols = columns();
    cols[0] = cols[0].copyWith(pin: ColumnPin.start);
    final controller = GridController<Product>(
      columns: cols,
      dataSource: InMemoryDataSource<Product>(sample()),
      frozenRowCount: 1,
    );
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: controller,
          showCheckboxColumn: true,
        ),
        size: const Size(600, 320),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Checkbox), findsWidgets);
  });

  testWidgets('a checkbox scrolls with its row', (tester) async {
    final rows = [for (var i = 0; i < 60; i++) Product('Row $i', 'Bulk', i)];
    final controller = grid(rows: rows);
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: controller,
          showCheckboxColumn: true,
        ),
        size: const Size(700, 320),
      ),
    );
    await tester.drag(find.text('Row 2'), const Offset(0, -300));
    await tester.pumpAndSettle();

    final visible = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((t) => t.startsWith('Row '))
        .toList();
    expect(visible.first, isNot('Row 0'));
    expect(tester.takeException(), isNull);
  });
}
