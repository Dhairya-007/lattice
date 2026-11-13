import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  List<GridColumn<Product>> cols({
    ColumnPin namePin = ColumnPin.none,
    bool hideCategory = false,
  }) =>
      [
        GridColumn<Product>(
          field: 'name',
          value: (p) => p.name,
          width: 100,
          pin: namePin,
        ),
        GridColumn<Product>(
          field: 'category',
          value: (p) => p.category,
          width: 100,
          visible: !hideCategory,
        ),
        GridColumn<Product>(field: 'price', value: (p) => p.price, width: 100),
        GridColumn<Product>(field: 'stock', value: (p) => p.stock, width: 100),
      ];

  const identity = HeaderRow([
    HeaderBand(title: 'Identity', fields: ['name', 'category']),
    HeaderBand(title: 'Numbers', fields: ['price', 'stock']),
  ]);

  List<HeaderBandLayout<Product>> layoutOf(
    HeaderRow row, {
    List<GridColumn<Product>>? columns,
    double viewport = 1000,
  }) {
    final layout = computeLayout<Product>(
      columns ?? cols(),
      viewportWidth: viewport,
    );
    return layoutHeaderRow<Product>(layout.scrolling, row);
  }

  group('spans', () {
    test('a band covers the width of the columns it names', () {
      final segments = layoutOf(identity);
      expect(segments.map((s) => s.band?.title), ['Identity', 'Numbers']);
      expect(segments.first.offset, 0);
      expect(segments.first.width, 200);
      expect(segments.last.offset, 200);
      expect(segments.last.width, 200);
    });

    test('a band knows which columns it ended up over', () {
      final segments = layoutOf(identity);
      expect(
        segments.first.columns.map((c) => c.column.field),
        ['name', 'category'],
      );
    });

    test('columns no band covers become a gap, not a crash', () {
      const row = HeaderRow([
        HeaderBand(title: 'Numbers', fields: ['price', 'stock']),
      ]);
      final segments = layoutOf(row);
      expect(segments.first.isGap, isTrue);
      expect(segments.first.width, 200);
      expect(segments.last.band!.title, 'Numbers');
    });

    test('a single-column band is as wide as that column', () {
      const row = HeaderRow([
        HeaderBand(title: 'Just price', fields: ['price']),
      ]);
      final priced = layoutOf(row).firstWhere((s) => !s.isGap);
      expect(priced.width, 100);
      expect(priced.offset, 200);
    });

    test('an empty pane produces nothing', () {
      expect(
        layoutHeaderRow<Product>(const [], identity),
        isEmpty,
      );
    });
  });

  group('the awkward cases', () {
    test('hiding a column shrinks the band over it', () {
      final segments = layoutOf(
        identity,
        columns: cols(hideCategory: true),
      );
      expect(segments.first.band!.title, 'Identity');
      expect(segments.first.width, 100);
      expect(segments.last.offset, 100);
    });

    test('a band split by a frozen pane is drawn in both panes', () {
      final layout = computeLayout<Product>(
        cols(namePin: ColumnPin.start),
        viewportWidth: 1000,
      );
      final leading = layoutHeaderRow<Product>(layout.leading, identity);
      final scrolling = layoutHeaderRow<Product>(layout.scrolling, identity);

      expect(leading.single.band!.title, 'Identity');
      expect(leading.single.width, 100);
      expect(scrolling.first.band!.title, 'Identity');
      expect(scrolling.first.width, 100);
    });

    test('an interrupted band becomes two segments, titled once', () {
      // The user has dragged 'price' into the middle of the Identity band.
      final reordered = [cols()[0], cols()[2], cols()[1], cols()[3]];
      final segments = layoutOf(identity, columns: reordered);

      final identitySegments =
          segments.where((s) => s.band?.title == 'Identity').toList();
      expect(identitySegments.length, 2);
      expect(identitySegments.first.isContinuation, isFalse);
      expect(identitySegments.last.isContinuation, isTrue);
    });

    test('the first band wins a column two bands both claim', () {
      const overlapping = HeaderRow([
        HeaderBand(title: 'First', fields: ['name', 'category']),
        HeaderBand(title: 'Second', fields: ['category', 'price']),
      ]);
      final segments = layoutOf(overlapping);
      expect(segments.first.band!.title, 'First');
      expect(segments.first.width, 200, reason: 'First keeps category');
      expect(segments[1].band!.title, 'Second');
      expect(segments[1].width, 100, reason: 'Second is left with price');
    });

    test('an unknown field simply covers nothing', () {
      const row = HeaderRow([
        HeaderBand(title: 'Ghost', fields: ['nope', 'price']),
      ]);
      final covered = layoutOf(row).firstWhere((s) => !s.isGap);
      expect(covered.width, 100);
      expect(covered.columns.single.column.field, 'price');
    });

    test('segments tile the pane exactly, with no gaps or overlaps', () {
      final segments = layoutOf(
        const HeaderRow([
          HeaderBand(title: 'Ends', fields: ['name', 'stock']),
        ]),
      );
      var cursor = 0.0;
      for (final segment in segments) {
        expect(segment.offset, cursor);
        cursor = segment.end;
      }
      expect(cursor, 400);
    });
  });

  group('validation', () {
    test('reports an unknown column', () {
      final problems = describeHeaderProblems<Product>(
        const [
          HeaderRow([
            HeaderBand(title: 'Oops', fields: ['nope'])
          ]),
        ],
        cols(),
      );
      expect(problems.single, contains('unknown column "nope"'));
    });

    test('reports a column two bands both cover', () {
      final problems = describeHeaderProblems<Product>(
        const [
          HeaderRow([
            HeaderBand(title: 'A', fields: ['name']),
            HeaderBand(title: 'B', fields: ['name']),
          ]),
        ],
        cols(),
      );
      expect(problems.single, contains('covered by both "A" and "B"'));
    });

    test('reports a band that spans nothing', () {
      final problems = describeHeaderProblems<Product>(
        const [
          HeaderRow([HeaderBand(title: 'Empty', fields: [])]),
        ],
        cols(),
      );
      expect(problems.single, contains('spans no columns'));
    });

    test('says nothing about a correct header', () {
      expect(
        describeHeaderProblems<Product>(const [identity], cols()),
        isEmpty,
      );
    });
  });

  group('through the controller', () {
    test('rows round-trip and notify', () {
      final grid = GridController<Product>(
        columns: cols(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        stackedHeaders: const [identity],
      );
      expect(grid.stackedHeaders.single.bands.length, 2);

      var notified = 0;
      grid.addListener(() => notified++);
      grid.stackedHeaders = const [
        HeaderRow([
          HeaderBand(title: 'All', fields: ['name'])
        ]),
      ];
      expect(notified, 1);
      expect(grid.stackedHeaders.single.bands.single.title, 'All');
    });

    test('the exposed list cannot be mutated from outside', () {
      final grid = GridController<Product>(
        columns: cols(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        stackedHeaders: const [identity],
      );
      expect(
        () => grid.stackedHeaders.add(const HeaderRow([])),
        throwsUnsupportedError,
      );
    });

    test('a bad header is caught in development', () {
      final grid = GridController<Product>(
        columns: cols(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
      );
      expect(
        () => grid.stackedHeaders = const [
          HeaderRow([
            HeaderBand(title: 'Oops', fields: ['nope'])
          ]),
        ],
        throwsStateError,
      );
    });

    test('bands follow a column move', () {
      final grid = GridController<Product>(
        columns: cols(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        stackedHeaders: const [identity],
      );
      grid.moveColumn('price', 0);
      final segments = layoutHeaderRow<Product>(
        grid.layoutFor(1000).scrolling,
        grid.stackedHeaders.single,
      );
      expect(segments.first.band!.title, 'Numbers');
      expect(segments.first.width, 100);
    });
  });
}
