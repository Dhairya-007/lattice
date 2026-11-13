import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_flutter/lattice_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'data_grid_test.dart' show Product, columns, host, sample;

GridController<Product> make({List<GridColumn<Product>>? cols}) {
  return GridController<Product>(
    columns: cols ?? columns(),
    dataSource: InMemoryDataSource<Product>(sample()),
  );
}

/// Opens the menu on the header whose title is [title].
Future<void> openMenu(WidgetTester tester, String title) async {
  final header = find.ancestor(
    of: find.text(title),
    matching: find.byType(LatticeHeaderCell<Product>),
  );
  // By icon: the menu's value type is private, so byType cannot name it.
  await tester.tap(
    find.descendant(of: header, matching: find.byIcon(Icons.more_vert_rounded)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the menu is there by default and can be turned off', (
    tester,
  ) async {
    await tester.pumpWidget(host(LatticeDataGrid<Product>(controller: make())));
    expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(3));

    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: make(), showColumnMenu: false)),
    );
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
  });

  testWidgets('sorting from the menu', (tester) async {
    final controller = make();
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    await openMenu(tester, 'Price');
    await tester.tap(find.text('Sort descending'));
    await tester.pumpAndSettle();

    expect(controller.sorts.single.field, 'price');
    expect(controller.sorts.single.isAscending, isFalse);
  });

  testWidgets('clear sort appears only once a sort exists', (tester) async {
    final controller = make();
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    await openMenu(tester, 'Price');
    expect(find.text('Clear sort'), findsNothing);
    await tester.tap(find.text('Sort ascending'));
    await tester.pumpAndSettle();

    await openMenu(tester, 'Price');
    expect(find.text('Clear sort'), findsOneWidget);
    await tester.tap(find.text('Clear sort'));
    await tester.pumpAndSettle();
    expect(controller.sorts, isEmpty);
  });

  testWidgets('pinning from the menu moves the column into a pane', (
    tester,
  ) async {
    final controller = make();
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    await openMenu(tester, 'Price');
    await tester.tap(find.text('Pin to the end'));
    await tester.pumpAndSettle();

    expect(controller.column('price')!.pin, ColumnPin.end);
    expect(controller.layoutFor(900).trailing.single.column.field, 'price');
  });

  testWidgets('unpin only offered for a pinned column', (tester) async {
    final cols = columns();
    cols[0] = cols[0].copyWith(pin: ColumnPin.start);
    final controller = make(cols: cols);
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    await openMenu(tester, 'Category');
    expect(find.text('Unpin'), findsNothing);
    await tester.tap(find.text('Pin to the start'));
    await tester.pumpAndSettle();

    await openMenu(tester, 'Category');
    expect(find.text('Unpin'), findsOneWidget);
  });

  testWidgets('hiding a column removes it', (tester) async {
    final controller = make();
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    await openMenu(tester, 'Category');
    await tester.tap(find.text('Hide column'));
    await tester.pumpAndSettle();

    expect(find.text('Category'), findsNothing);
    expect(controller.visibleColumns.length, 2);
  });

  testWidgets('the chooser brings a hidden column back', (tester) async {
    final controller = make();
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    controller.setColumnVisible('category', false);
    await tester.pumpAndSettle();
    expect(find.text('Category'), findsNothing);

    await openMenu(tester, 'Name');
    await tester.tap(find.text('Choose columns…'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(SwitchListTile),
        matching: find.text('Category'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.column('category')!.visible, isTrue);
  });

  testWidgets('the last visible column cannot be hidden', (tester) async {
    final controller = make();
    controller.setColumnVisible('category', false);
    controller.setColumnVisible('price', false);
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );

    await openMenu(tester, 'Name');
    await tester.tap(find.text('Choose columns…'));
    await tester.pumpAndSettle();

    final nameSwitch = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('Name'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(nameSwitch.onChanged, isNull);
  });

  testWidgets('reorder is off unless asked for', (tester) async {
    await tester.pumpWidget(host(LatticeDataGrid<Product>(controller: make())));
    expect(find.byType(Draggable<String>), findsNothing);

    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: make(), allowColumnReorder: true),
      ),
    );
    expect(find.byType(Draggable<String>), findsNWidgets(3));
  });

  testWidgets('dragging a header onto another reorders them', (tester) async {
    final controller = make();
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: controller,
          allowColumnReorder: true,
        ),
      ),
    );
    expect(controller.visibleFields, ['name', 'category', 'price']);

    final from = tester.getCenter(find.text('Price'));
    final to = tester.getCenter(find.text('Name'));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.visibleFields.first, 'price');
  });

  testWidgets('dragging into a pinned pane pins the column', (tester) async {
    final cols = columns();
    cols[0] = cols[0].copyWith(pin: ColumnPin.start);
    final controller = make(cols: cols);
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: controller,
          allowColumnReorder: true,
        ),
        size: const Size(800, 400),
      ),
    );
    expect(controller.column('price')!.pin, ColumnPin.none);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Price')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveTo(tester.getCenter(find.text('Name')));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.column('price')!.pin, ColumnPin.start);
  });
}
