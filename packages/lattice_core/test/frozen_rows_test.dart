import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  GridController<Product> grid({
    int top = 0,
    int bottom = 0,
    List<Product>? rows,
    List<SortSpec> sorts = const [],
    List<GroupSpec> groups = const [],
  }) {
    return GridController<Product>(
      columns: productColumns(),
      dataSource: InMemoryDataSource<Product>(rows ?? sampleProducts()),
      frozenRowCount: top,
      frozenRowCountBottom: bottom,
      sorts: sorts,
      groups: groups,
    );
  }

  List<String> namesOf(List<GridRow<Product>> rows) => [
        for (final row in rows)
          if (row is DataGridRow<Product>) row.data.name else 'GROUP',
      ];

  group('splitting the rows', () {
    test('nothing is frozen by default', () {
      final g = grid();
      expect(g.effectiveFrozenTop, 0);
      expect(g.effectiveFrozenBottom, 0);
      expect(g.frozenTopRows, isEmpty);
      expect(g.frozenBottomRows, isEmpty);
      expect(g.scrollableRows.length, 6);
    });

    test('the top band comes off the front', () {
      final g = grid(top: 2);
      expect(namesOf(g.frozenTopRows), ['Keyboard', 'Mouse']);
      expect(namesOf(g.scrollableRows).first, 'Monitor');
      expect(g.scrollableRows.length, 4);
    });

    test('the bottom band comes off the end', () {
      final g = grid(bottom: 2);
      expect(namesOf(g.frozenBottomRows), ['Dock', 'Webcam']);
      expect(namesOf(g.scrollableRows).last, 'Laptop');
    });

    test('both bands at once leave the middle scrolling', () {
      final g = grid(top: 1, bottom: 1);
      expect(namesOf(g.frozenTopRows), ['Keyboard']);
      expect(namesOf(g.frozenBottomRows), ['Webcam']);
      expect(namesOf(g.scrollableRows), ['Mouse', 'Monitor', 'Laptop', 'Dock']);
    });

    test('the three bands always reconstruct the visible rows', () {
      for (final pair in [(0, 0), (1, 0), (0, 1), (2, 2), (5, 5)]) {
        final g = grid(top: pair.$1, bottom: pair.$2);
        expect(
          [...g.frozenTopRows, ...g.scrollableRows, ...g.frozenBottomRows]
              .length,
          g.rowCount,
          reason: 'with top ${pair.$1} and bottom ${pair.$2}',
        );
      }
    });
  });

  group('refusing to freeze everything', () {
    test('freezing more rows than exist leaves one scrolling', () {
      final g = grid(top: 99);
      expect(g.effectiveFrozenTop, 5);
      expect(g.scrollableRows.length, 1);
    });

    test('the top band wins when the two would overlap', () {
      final g = grid(top: 4, bottom: 4);
      expect(g.effectiveFrozenTop, 4);
      expect(g.effectiveFrozenBottom, 1);
      expect(g.scrollableRows.length, 1);
    });

    test('an empty grid freezes nothing', () {
      final g = grid(top: 3, bottom: 3, rows: []);
      expect(g.effectiveFrozenTop, 0);
      expect(g.effectiveFrozenBottom, 0);
      expect(g.scrollableRows, isEmpty);
    });

    test('a single row is never frozen away entirely', () {
      final g = grid(
        top: 1,
        rows: [Product(id: 1, name: 'Only', category: 'X', price: 1)],
      );
      expect(g.effectiveFrozenTop, 0);
      expect(namesOf(g.scrollableRows), ['Only']);
    });

    test('a negative count is treated as none', () {
      final g = grid();
      g.frozenRowCount = -5;
      expect(g.frozenRowCount, 0);
      expect(g.effectiveFrozenTop, 0);
    });
  });

  group('freezing by position, not identity', () {
    test('sorting changes which rows are pinned', () {
      final g = grid(top: 1);
      expect(namesOf(g.frozenTopRows), ['Keyboard']);
      g.setSorts(const [SortSpec('price')]);
      expect(namesOf(g.frozenTopRows), ['Mouse']);
    });

    test('filtering re-picks the pinned rows', () {
      final g = grid(top: 1);
      g.setSearch('Compute');
      expect(namesOf(g.frozenTopRows), ['Laptop']);
    });

    test('paging pins the first row of the current page', () {
      final g = grid(top: 1);
      g.setPageSize(2);
      expect(namesOf(g.frozenTopRows), ['Keyboard']);
      g.nextPage();
      expect(namesOf(g.frozenTopRows), ['Monitor']);
    });

    test('a group header can be the pinned row', () {
      final g = grid(top: 1, groups: [const GroupSpec('category')]);
      expect(g.frozenTopRows.single, isA<GroupGridRow<Product>>());
    });
  });

  group('isRowFrozen', () {
    test('identifies both bands and the middle', () {
      final g = grid(top: 2, bottom: 1);
      expect(g.isRowFrozen(0), isTrue);
      expect(g.isRowFrozen(1), isTrue);
      expect(g.isRowFrozen(2), isFalse);
      expect(g.isRowFrozen(4), isFalse);
      expect(g.isRowFrozen(5), isTrue);
    });

    test('nothing is frozen when nothing is pinned', () {
      final g = grid();
      for (var i = 0; i < g.rowCount; i++) {
        expect(g.isRowFrozen(i), isFalse);
      }
    });
  });

  group('notification', () {
    test('changing a count notifies once', () {
      final g = grid();
      var notified = 0;
      g.addListener(() => notified++);
      g.frozenRowCount = 2;
      expect(notified, 1);
      expect(g.effectiveFrozenTop, 2);
    });

    test('setting the same count does not notify', () {
      final g = grid(top: 2);
      var notified = 0;
      g.addListener(() => notified++);
      g.frozenRowCount = 2;
      expect(notified, 0);
    });
  });
}
