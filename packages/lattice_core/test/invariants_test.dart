// Invariants that must hold for *any* arrangement of the grid, checked
// against randomly generated ones.
//
// The five bugs fixed in 0.3.0 were all of this shape: each held for the
// arrangement someone happened to try and broke for another. An
// example-based test proves one case; these state the rule and let the
// generator look for the case that breaks it.
//
// The seed is fixed, so a failure is reproducible and CI cannot go red for a
// different reason than it went red locally. Raise [kCases] when hunting.
import 'dart:math';

import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const int kCases = 120;
const int kSeed = 20261114;

/// One randomly generated arrangement of the grid.
class Arrangement {
  Arrangement(Random random)
      : sorts = _sorts(random),
        search = _search(random),
        filter = _filter(random),
        groups = _groups(random),
        pageSize = _pageSize(random),
        pins = _pins(random),
        hidden = _hidden(random);

  final List<SortSpec> sorts;
  final String search;
  final FilterCondition? filter;
  final List<GroupSpec> groups;
  final int? pageSize;
  final Map<String, ColumnPin> pins;
  final Set<String> hidden;

  static const _fields = ['name', 'category', 'price', 'stock', 'active'];

  static List<SortSpec> _sorts(Random random) {
    final count = random.nextInt(3);
    final fields = [..._fields]..shuffle(random);
    return [
      for (var i = 0; i < count; i++)
        SortSpec(
          fields[i],
          direction: random.nextBool()
              ? SortDirection.ascending
              : SortDirection.descending,
          nulls: random.nextBool() ? NullsPosition.first : NullsPosition.last,
        ),
    ];
  }

  static String _search(Random random) {
    const needles = ['', '', '', 'o', 'mo', 'e', 'zzz'];
    return needles[random.nextInt(needles.length)];
  }

  static FilterCondition? _filter(Random random) {
    if (random.nextInt(3) == 0) return null;
    const options = [
      FilterCondition(
        field: 'category',
        operator: FilterOperator.equals,
        value: 'Input',
      ),
      FilterCondition(
        field: 'price',
        operator: FilterOperator.greaterThan,
        value: 70,
      ),
      FilterCondition(
        field: 'stock',
        operator: FilterOperator.isNotNull,
      ),
      FilterCondition(
        field: 'active',
        operator: FilterOperator.equals,
        value: true,
      ),
    ];
    return options[random.nextInt(options.length)];
  }

  static List<GroupSpec> _groups(Random random) {
    switch (random.nextInt(4)) {
      case 0:
        return const [GroupSpec('category')];
      case 1:
        return const [GroupSpec('active'), GroupSpec('category')];
      case 2:
        return [GroupSpec('price', keyOf: dear)];
      default:
        return const [];
    }
  }

  static int? _pageSize(Random random) {
    const sizes = [null, null, 1, 2, 4, 100];
    return sizes[random.nextInt(sizes.length)];
  }

  static Map<String, ColumnPin> _pins(Random random) {
    final pins = <String, ColumnPin>{};
    for (final field in _fields) {
      switch (random.nextInt(6)) {
        case 0:
          pins[field] = ColumnPin.start;
        case 1:
          pins[field] = ColumnPin.end;
        default:
          break;
      }
    }
    return pins;
  }

  static Set<String> _hidden(Random random) {
    final hidden = <String>{};
    for (final field in _fields) {
      // Never hide them all: a grid with no columns is its own test.
      if (random.nextInt(8) == 0 && hidden.length < 3) hidden.add(field);
    }
    return hidden;
  }

  /// Builds a controller in this arrangement.
  GridController<Product> build({bool identified = true}) {
    final grid = productGrid(
      identified: identified,
      selectionMode: SelectionMode.cellRange,
    );
    grid.batch(() {
      grid.setSorts(sorts);
      grid.setSearch(search);
      if (filter != null) grid.setFilter(filter);
      grid.setGroups(groups);
      grid.setPageSize(pageSize);
      for (final entry in pins.entries) {
        grid.setColumnPin(entry.key, entry.value);
      }
      for (final field in hidden) {
        grid.setColumnVisible(field, false);
      }
    });
    return grid;
  }

  @override
  String toString() => 'Arrangement(sorts: $sorts, search: "$search", '
      'filter: $filter, groups: $groups, pageSize: $pageSize, '
      'pins: $pins, hidden: $hidden)';
}

void main() {
  final random = Random(kSeed);
  final arrangements = [for (var i = 0; i < kCases; i++) Arrangement(random)];

  test('group counts add up to the number of rows that matched', () {
    for (final arrangement in arrangements) {
      final grid = arrangement.build();
      if (!grid.isGrouped) continue;
      final headers = grid.visibleRows.whereType<GroupGridRow<Product>>();
      final top = [
        for (final h in headers)
          if (h.depth == 0) h
      ];
      final counted = top.fold<int>(0, (sum, h) => sum + h.rowCount);
      expect(counted, grid.matchedCount, reason: '$arrangement');
    }
  });

  test('every data row on screen is a row the filters admitted', () {
    for (final arrangement in arrangements) {
      final grid = arrangement.build();
      final shown = [
        for (final row in grid.visibleRows)
          if (row is DataGridRow<Product>) row.data,
      ];
      expect(shown.length, lessThanOrEqualTo(grid.matchedCount),
          reason: '$arrangement');
      final filter = arrangement.filter;
      if (filter != null) {
        for (final row in shown) {
          expect(
            filter.matchesRow((f) => grid.column(f)?.value(row)),
            isTrue,
            reason: '${row.name} fails the filter in $arrangement',
          );
        }
      }
    }
  });

  test('the export has the same columns as the screen, in the same order', () {
    for (final arrangement in arrangements) {
      final grid = arrangement.build();
      // Compared against the layout, not against visibleFields: the layout is
      // what gets painted, so it is the only ground truth for "the screen".
      // Checking one derived order against another would pass while both
      // were wrong together, which is how bug D survived.
      final onScreen = [
        for (final c in grid.layoutFor(1800).allColumns) c.column.title,
      ];
      if (onScreen.isEmpty) continue;
      expect(
        grid.exportCsv().split('\r\n').first.split(','),
        onScreen,
        reason: '$arrangement',
      );
    }
  });

  test('the laid-out panes are the display order, split in three', () {
    for (final arrangement in arrangements) {
      final grid = arrangement.build();
      final laid = [
        for (final c in grid.layoutFor(1800).allColumns) c.column.field,
      ];
      expect(laid, grid.visibleFields, reason: '$arrangement');
    }
  });

  test('arrow keys walk the columns one screen position at a time', () {
    for (final arrangement in arrangements) {
      final grid = arrangement.build();
      // Taken from the layout for the same reason the export invariant is.
      final fields = [
        for (final c in grid.layoutFor(1800).allColumns) c.column.field,
      ];
      if (fields.isEmpty || grid.rowCount == 0) continue;
      grid.selectCell(CellAddress(0, fields.first));
      for (var i = 1; i < fields.length; i++) {
        grid.moveActiveCell(0, 1);
        expect(grid.selection.activeCell!.field, fields[i],
            reason: '$arrangement');
      }
    }
  });

  test('selection stays on the same row across a re-sort', () {
    for (final arrangement in arrangements) {
      final grid = arrangement.build();
      final index = grid.visibleRows.indexWhere(
        (r) => r is DataGridRow<Product>,
      );
      if (index < 0) continue;
      grid.selectRow(index);
      final before = grid.selectedData.single.id;

      grid.setSorts([
        const SortSpec('price', direction: SortDirection.descending),
        const SortSpec('name'),
      ]);
      if (grid.selection.rowCount == 0) {
        // Only legitimate if that row is no longer on screen at all: a
        // paged grid can sort the row onto another page.
        final onScreen = [
          for (final row in grid.visibleRows)
            if (row is DataGridRow<Product>) row.data.id,
        ];
        expect(onScreen, isNot(contains(before)), reason: '$arrangement');
        continue;
      }
      expect(grid.selectedData.single.id, before, reason: '$arrangement');
    }
  });

  test('a page is a slice of the matched rows, and the pages cover them', () {
    for (final arrangement in arrangements) {
      final grid = arrangement.build();
      final size = grid.pageSize;
      if (size == null || grid.isGrouped) continue;
      final seen = <int>[];
      for (var page = 0; page < grid.pageCount; page++) {
        grid.goToPage(page);
        expect(grid.rowCount, lessThanOrEqualTo(size), reason: '$arrangement');
        seen.addAll([
          for (final row in grid.visibleRows)
            if (row is DataGridRow<Product>) row.data.id,
        ]);
      }
      expect(seen.length, grid.matchedCount, reason: '$arrangement');
      expect(seen.toSet().length, seen.length,
          reason: 'a row appeared on two pages in $arrangement');
    }
  });

  test('copying the whole visible range gives one line per data row', () {
    for (final arrangement in arrangements) {
      final grid = arrangement.build();
      final fields = grid.visibleFields;
      final rows = [
        for (final row in grid.visibleRows)
          if (row is DataGridRow<Product>) row,
      ];
      if (fields.isEmpty || rows.length < 2) continue;
      grid.selectCell(CellAddress(rows.first.index, fields.first));
      grid.extendSelectionTo(CellAddress(rows.last.index, fields.last));
      final lines = grid.copySelectionAsText().split('\n');
      // The range spans the group headers between the rows as well, so the
      // count is the span, not the row count.
      expect(lines.length, rows.last.index - rows.first.index + 1,
          reason: '$arrangement');
      for (final line in lines) {
        expect(line.split('\t').length, fields.length, reason: '$arrangement');
      }
    }
  });

  test('re-running the same arrangement gives the same rows', () {
    for (final arrangement in arrangements) {
      final first = labelsOf(arrangement.build());
      final second = labelsOf(arrangement.build());
      expect(first, second, reason: '$arrangement');
    }
  });

  test('a saved view restores the arrangement it saved', () {
    for (final arrangement in arrangements) {
      final grid = arrangement.build();
      final restored = productGrid(identified: true);
      restored.restoreState(
        grid.saveState(),
        resolveGroup: (g) => g.field == 'price' ? g.restore(keyOf: dear) : g,
      );
      expect(labelsOf(restored), labelsOf(grid), reason: '$arrangement');
      expect(restored.visibleFields, grid.visibleFields,
          reason: '$arrangement');
      expect(restored.matchedCount, grid.matchedCount, reason: '$arrangement');
    }
  });

  test('a notification about the selection never claims the rows changed', () {
    for (final arrangement in arrangements) {
      final grid = arrangement.build();
      if (grid.rowCount == 0) continue;
      final seen = <Set<GridChange>>[];
      grid.addChangeListener(seen.add);
      grid.selectRow(0);
      grid.clearSelection();
      for (final changes in seen) {
        expect(changes, {GridChange.selection}, reason: '$arrangement');
      }
    }
  });
}

Object? dear(Object? value) => (value as num) > 100;
