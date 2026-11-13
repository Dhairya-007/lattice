import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  List<GridColumn<Product>> columns({
    double width = 100,
    ColumnPin pin = ColumnPin.none,
  }) =>
      [
        GridColumn<Product>(
            field: 'name', value: (p) => p.name, width: width, pin: pin),
        GridColumn<Product>(
            field: 'category', value: (p) => p.category, width: width),
        GridColumn<Product>(
            field: 'price', value: (p) => p.price, width: width),
      ];

  group('widths and offsets', () {
    test('columns are laid out end to end', () {
      final layout = computeLayout(columns(), viewportWidth: 1000);
      expect(layout.scrolling.map((c) => c.offset), [0, 100, 200]);
      expect(layout.scrolling.map((c) => c.end), [100, 200, 300]);
      expect(layout.totalWidth, 300);
    });

    test('hidden columns take part in neither layout nor count', () {
      final withHidden = columns()..[1] = columns()[1].copyWith(visible: false);
      final layout = computeLayout(withHidden, viewportWidth: 1000);
      expect(layout.columnCount, 2);
      expect(layout.scrolling.map((c) => c.column.field), ['name', 'price']);
      expect(layout.scrolling.last.offset, 100);
    });

    test('a width override wins over the declared width', () {
      final layout = computeLayout(
        columns(),
        viewportWidth: 1000,
        widthOverrides: {'name': 250},
      );
      expect(layout.scrolling.first.width, 250);
      expect(layout.scrolling[1].offset, 250);
    });

    test('an override is clamped to the column bounds', () {
      final bounded = [
        GridColumn<Product>(
          field: 'name',
          value: (p) => p.name,
          width: 100,
          minWidth: 80,
          maxWidth: 200,
        ),
      ];
      expect(
        computeLayout(bounded,
            viewportWidth: 1000,
            widthOverrides: {'name': 20}).scrolling.first.width,
        80,
      );
      expect(
        computeLayout(bounded,
            viewportWidth: 1000,
            widthOverrides: {'name': 9999}).scrolling.first.width,
        200,
      );
    });
  });

  group('frozen panes', () {
    test('pinned columns are split out and offset within their own pane', () {
      final pinned = [
        columns()[0].copyWith(pin: ColumnPin.start),
        columns()[1],
        columns()[2].copyWith(pin: ColumnPin.end),
      ];
      final layout = computeLayout(pinned, viewportWidth: 1000);
      expect(layout.leading.map((c) => c.column.field), ['name']);
      expect(layout.scrolling.map((c) => c.column.field), ['category']);
      expect(layout.trailing.map((c) => c.column.field), ['price']);
      expect(layout.leading.first.offset, 0);
      expect(layout.trailing.first.offset, 0);
      expect(layout.leadingWidth, 100);
      expect(layout.trailingWidth, 100);
    });

    test('the scrolling viewport is what the frozen panes leave over', () {
      final pinned = [
        columns()[0].copyWith(pin: ColumnPin.start),
        columns()[1],
        columns()[2].copyWith(pin: ColumnPin.end),
      ];
      final layout = computeLayout(pinned, viewportWidth: 500);
      expect(layout.scrollViewportWidth, 300);
    });

    test('frozen panes wider than the viewport leave no negative space', () {
      final layout = computeLayout(
        columns(pin: ColumnPin.start),
        viewportWidth: 50,
      );
      expect(layout.scrollViewportWidth, 0);
    });
  });

  group('ColumnFit', () {
    test('none leaves the natural widths and scrolls', () {
      final layout = computeLayout(columns(), viewportWidth: 900);
      expect(layout.totalWidth, 300);
    });

    test('stretch fills the viewport exactly', () {
      final layout = computeLayout(
        columns(),
        viewportWidth: 900,
        fit: ColumnFit.stretch,
      );
      expect(layout.totalWidth, closeTo(900, 0.001));
      expect(layout.scrolling.map((c) => c.width),
          everyElement(closeTo(300, 0.001)));
    });

    test(
        'stretch respects maxWidth and hands the remainder to a growable column',
        () {
      final capped = [
        GridColumn<Product>(
          field: 'name',
          value: (p) => p.name,
          width: 100,
          maxWidth: 120,
        ),
        GridColumn<Product>(
            field: 'category', value: (p) => p.category, width: 100),
      ];
      final layout =
          computeLayout(capped, viewportWidth: 400, fit: ColumnFit.stretch);
      expect(layout.scrolling.first.width, 120);
      expect(layout.totalWidth, closeTo(400, 0.001));
    });

    test('lastColumn grows only the final column', () {
      final layout = computeLayout(
        columns(),
        viewportWidth: 900,
        fit: ColumnFit.lastColumn,
      );
      expect(layout.scrolling.first.width, 100);
      expect(layout.scrolling.last.width, 700);
    });

    test('a viewport narrower than the columns is left alone', () {
      final layout = computeLayout(
        columns(),
        viewportWidth: 200,
        fit: ColumnFit.stretch,
      );
      expect(layout.totalWidth, 300);
    });
  });

  group('horizontal windowing', () {
    final many = [
      for (var i = 0; i < 50; i++)
        GridColumn<Product>(field: 'c$i', value: (p) => p.id, width: 100),
    ];

    test('only columns intersecting the viewport are built', () {
      final layout = computeLayout(many, viewportWidth: 500);
      final visible = layout.visibleScrollingColumns(
        scrollOffset: 1000,
        overscan: 0,
      );
      expect(visible.map((c) => c.column.field), [
        'c10',
        'c11',
        'c12',
        'c13',
        'c14',
      ]);
    });

    test('overscan widens the window on both sides', () {
      final layout = computeLayout(many, viewportWidth: 500);
      final visible = layout.visibleScrollingColumns(
        scrollOffset: 1000,
        overscan: 1,
      );
      expect(visible.first.column.field, 'c9');
      expect(visible.last.column.field, 'c15');
    });

    test('the window clamps at the edges', () {
      final layout = computeLayout(many, viewportWidth: 500);
      expect(
        layout
            .visibleScrollingColumns(scrollOffset: 0, overscan: 2)
            .first
            .column
            .field,
        'c0',
      );
      expect(
        layout
            .visibleScrollingColumns(scrollOffset: 4500, overscan: 2)
            .last
            .column
            .field,
        'c49',
      );
    });

    test('no columns or no width yields nothing', () {
      expect(
        computeLayout(<GridColumn<Product>>[], viewportWidth: 500)
            .visibleScrollingColumns(scrollOffset: 0),
        isEmpty,
      );
      expect(
        computeLayout(many, viewportWidth: 0)
            .visibleScrollingColumns(scrollOffset: 0),
        isEmpty,
      );
    });
  });

  group('GridColumn', () {
    test('derives a readable title from the field name', () {
      expect(GridColumn<Product>(field: 'unitPrice', value: (p) => 0).title,
          'Unit Price');
      expect(GridColumn<Product>(field: 'unit_price', value: (p) => 0).title,
          'Unit Price');
      expect(
          GridColumn<Product>(field: 'price', value: (p) => 0).title, 'Price');
    });

    test('numbers align to the end by default', () {
      expect(
        GridColumn<Product>(
                field: 'price', value: (p) => 0, type: ColumnType.number)
            .effectiveAlign,
        ColumnAlign.end,
      );
      expect(
        GridColumn<Product>(field: 'name', value: (p) => '').effectiveAlign,
        ColumnAlign.start,
      );
    });

    test('a column is editable exactly when it has a setter', () {
      expect(GridColumn<Product>(field: 'name', value: (p) => '').editable,
          isFalse);
      expect(productColumnMap()['name']!.editable, isTrue);
    });

    test('formattedValue runs the formatter and maps null to empty text', () {
      final price = productColumnMap()['price']!;
      expect(
        price.formattedValue(
          Product(id: 1, name: 'x', category: 'y', price: 12.5),
        ),
        '12.50 USD',
      );
      expect(
        productColumnMap()['stock']!.formattedValue(
          Product(id: 1, name: 'x', category: 'y', price: 0),
        ),
        '',
      );
    });

    test('a Map row is read by field when no accessor is given', () {
      final column = GridColumn<Map<String, Object?>>(field: 'name');
      expect(column.value({'name': 'Keyboard'}), 'Keyboard');
    });

    test('a non-Map row without an accessor fails loudly', () {
      final column = GridColumn<Product>(field: 'name');
      expect(
        () => column.value(
          Product(id: 1, name: 'x', category: 'y', price: 0),
        ),
        throwsStateError,
      );
    });

    test('copyWith keeps untouched fields', () {
      final original = productColumnMap()['price']!;
      final copy = original.copyWith(width: 300);
      expect(copy.width, 300);
      expect(copy.field, 'price');
      expect(copy.type, ColumnType.number);
      expect(copy.editable, isTrue);
    });
  });
}
