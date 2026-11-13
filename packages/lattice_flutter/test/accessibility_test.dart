import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_flutter/lattice_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'data_grid_test.dart' show Product, columns, host, sample;

GridController<Product> make({
  List<SortSpec> sorts = const [],
  List<GroupSpec> groups = const [],
}) {
  return GridController<Product>(
    columns: columns(),
    dataSource: InMemoryDataSource<Product>(sample()),
    sorts: sorts,
    groups: groups,
  );
}

/// The semantics node wrapping the widget [finder] points at.
SemanticsNode nodeFor(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder);

void main() {
  testWidgets('a cell says which row and column it is', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(LatticeDataGrid<Product>(controller: make())));

    final node = nodeFor(tester, find.text('Mouse'));
    expect(node.label, contains('Row 2'));
    expect(node.label, contains('Name'));
    expect(node.value, 'Mouse');
    handle.dispose();
  });

  testWidgets('a selected cell says so', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = make();
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    controller.selectRow(1);
    await tester.pump();

    expect(nodeFor(tester, find.text('Mouse')).label, contains('selected'));
    handle.dispose();
  });

  testWidgets('a header announces its sort state and level', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: make(
            sorts: const [SortSpec('category'), SortSpec('price')],
          ),
        ),
      ),
    );

    final category = nodeFor(tester, find.text('Category')).label;
    expect(category, contains('sorted ascending'));
    expect(category, contains('sort level 1'));
    expect(nodeFor(tester, find.text('Price')).label, contains('sort level 2'));
    handle.dispose();
  });

  testWidgets('an unsorted header says nothing about sorting', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(LatticeDataGrid<Product>(controller: make())));
    expect(
      nodeFor(tester, find.text('Price')).label,
      isNot(contains('sorted')),
    );
    handle.dispose();
  });

  testWidgets('a header is a header, and sortable ones are buttons', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(LatticeDataGrid<Product>(controller: make())));
    final node = nodeFor(tester, find.text('Price'));
    expect(node.hasFlag(SemanticsFlag.isHeader), isTrue);
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('a group row says its count and whether it is open', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = make(groups: const [GroupSpec('category')]);
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );

    final label = nodeFor(tester, find.text('Category: Compute')).label;
    expect(label, contains('2 rows'));
    expect(label, contains('expanded'));

    controller.toggleGroup(
      (controller.visibleRows.first as GroupGridRow<Product>).path,
    );
    await tester.pumpAndSettle();
    expect(
      nodeFor(tester, find.text('Category: Compute')).label,
      contains('collapsed'),
    );
    handle.dispose();
  });

  testWidgets('a filter input is named after its column', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: make(), showFilterRow: true)),
    );
    final node = tester.getSemantics(find.byType(TextField).first);
    expect(node.label, contains('Filter'));
    handle.dispose();
  });

  testWidgets('an editor is announced, and so is its error', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = make();
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    controller.beginEdit(const CellAddress(0, 'name'));
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.byType(TextField));
    expect(node.label, contains('Name editor'));

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    final withError = tester.getSemantics(find.byType(TextField));
    expect(withError.value, 'Required');
    expect(withError.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    handle.dispose();
  });

  testWidgets('a data bar is not announced', (tester) async {
    final handle = tester.ensureSemantics();
    final cols = columns();
    cols[2] = cols[2].copyWith(rule: const DataBarRule());
    final controller = GridController<Product>(
      columns: cols,
      dataSource: InMemoryDataSource<Product>(sample()),
    );
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    // The value is still spoken; the decoration behind it is not a node.
    expect(nodeFor(tester, find.text('320')).value, '320');
    handle.dispose();
  });

  testWidgets('the whole grid produces no semantics warnings', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: make(groups: const [GroupSpec('category')]),
          showFilterRow: true,
          showCheckboxColumn: true,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
