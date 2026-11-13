import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_flutter/lattice_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'data_grid_test.dart' show Product, columns, host, sample;

const identity = HeaderRow([
  HeaderBand(title: 'Identity', fields: ['name', 'category']),
  HeaderBand(title: 'Money', fields: ['price']),
]);

GridController<Product> stacked({
  List<HeaderRow> rows = const [identity],
  List<GridColumn<Product>>? cols,
}) {
  return GridController<Product>(
    columns: cols ?? columns(),
    dataSource: InMemoryDataSource<Product>(sample()),
    stackedHeaders: rows,
  );
}

void main() {
  testWidgets('a band is drawn above the columns it covers', (tester) async {
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: stacked())),
    );

    expect(find.text('Identity'), findsOneWidget);
    expect(find.text('Money'), findsOneWidget);

    // The band sits above the column titles it covers, and spans both.
    final band = tester.getRect(find.text('Identity'));
    final name = tester.getRect(find.text('Name'));
    final category = tester.getRect(find.text('Category'));
    expect(band.bottom, lessThanOrEqualTo(name.top));
    expect(band.center.dx, closeTo((name.left + category.right) / 2, 40));
  });

  testWidgets('the band is as wide as its columns together', (tester) async {
    final controller = stacked();
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    final layout = controller.layoutFor(900);
    final segments = layoutHeaderRow<Product>(layout.scrolling, identity);
    final identitySegment = segments.firstWhere(
      (s) => s.band?.title == 'Identity',
    );
    expect(identitySegment.width, 280);
  });

  testWidgets('several rows stack outermost first', (tester) async {
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(
          controller: stacked(
            rows: const [
              HeaderRow([
                HeaderBand(
                  title: 'Everything',
                  fields: ['name', 'category', 'price'],
                ),
              ]),
              identity,
            ],
          ),
        ),
      ),
    );
    final outer = tester.getRect(find.text('Everything'));
    final inner = tester.getRect(find.text('Identity'));
    final title = tester.getRect(find.text('Name'));
    expect(outer.top, lessThan(inner.top));
    expect(inner.top, lessThan(title.top));
  });

  testWidgets('hiding a column narrows the band over it', (tester) async {
    final controller = stacked();
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: controller)),
    );
    final before = tester.getRect(find.text('Identity'));

    controller.setColumnVisible('category', false);
    await tester.pumpAndSettle();

    expect(find.text('Category'), findsNothing);
    expect(find.text('Identity'), findsOneWidget);
    final after = tester.getRect(find.text('Identity'));
    expect(after.center.dx, lessThan(before.center.dx));
  });

  testWidgets('a band split by a frozen pane is titled once', (tester) async {
    final cols = columns();
    cols[0] = cols[0].copyWith(pin: ColumnPin.start);
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: stacked(cols: cols)),
        size: const Size(700, 400),
      ),
    );
    // 'Identity' spans the frozen 'name' and the scrolling 'category': two
    // segments, one title.
    expect(find.text('Identity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no stacked headers means no extra rows', (tester) async {
    await tester.pumpWidget(
      host(LatticeDataGrid<Product>(controller: stacked(rows: const []))),
    );
    expect(find.text('Identity'), findsNothing);
    final name = tester.getRect(find.text('Name'));
    expect(name.top, lessThan(60), reason: 'header is still at the top');
  });

  testWidgets('stacked headers scroll with the columns', (tester) async {
    final wide = [
      for (var i = 0; i < 12; i++)
        GridColumn<Product>(field: 'c$i', value: (p) => p.name, width: 120),
    ];
    final controller = GridController<Product>(
      columns: wide,
      dataSource: InMemoryDataSource<Product>(sample()),
      stackedHeaders: const [
        HeaderRow([
          HeaderBand(title: 'First half', fields: ['c0', 'c1', 'c2']),
          HeaderBand(title: 'Second half', fields: ['c9', 'c10', 'c11']),
        ]),
      ],
    );
    await tester.pumpWidget(
      host(
        LatticeDataGrid<Product>(controller: controller),
        size: const Size(500, 400),
      ),
    );
    final before = tester.getRect(find.text('First half')).left;

    await tester.drag(find.text('C3'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('First half')).left, lessThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a header with no column is reported in development', (
    tester,
  ) async {
    final controller = stacked(rows: const []);
    expect(
      () => controller.stackedHeaders = const [
        HeaderRow([
          HeaderBand(title: 'Ghost', fields: ['missing']),
        ]),
      ],
      throwsStateError,
    );
  });
}
