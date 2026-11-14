import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// A synchronous source that is not [InMemoryDataSource], which is what the
/// controller used to require before it asked about capabilities.
class SyncSource extends LatticeDataSource<Product> {
  SyncSource(this.rows);

  final List<Product> rows;
  int asyncFetches = 0;

  @override
  bool get isLocal => true;

  @override
  bool get isSynchronous => true;

  @override
  GridResult<Product> fetchSync(GridQuery query) => GridResult<Product>(
        rows: List<Product>.of(rows),
        totalCount: rows.length,
      );

  @override
  Future<GridResult<Product>> fetch(GridQuery query) async {
    asyncFetches++;
    return fetchSync(query);
  }
}

void main() {
  group('one display order', () {
    test(
        'the layout, the fields and the export agree once a column is '
        'pinned', () {
      final grid = productGrid();
      grid.setColumnPin('price', ColumnPin.start);
      grid.setColumnPin('name', ColumnPin.end);

      final layout = grid.layoutFor(2000);
      final fromLayout = [for (final c in layout.allColumns) c.column.field];
      expect(fromLayout, grid.visibleFields);
      expect(
        grid.exportCsv().split('\r\n').first.split(','),
        [for (final f in grid.visibleFields) grid.column(f)!.title],
      );
    });

    test('a laid-out column index is its position on screen', () {
      final grid = productGrid();
      grid.setColumnPin('stock', ColumnPin.start);
      final layout = grid.layoutFor(2000);
      for (final laid in layout.allColumns) {
        expect(laid.index, grid.visibleFields.indexOf(laid.column.field));
      }
    });

    test('lastColumn fit grows the last column on screen', () {
      final grid = productGrid()..columnFit = ColumnFit.lastColumn;
      grid.setColumnPin('name', ColumnPin.end);
      final layout = grid.layoutFor(2000);
      // 'name' is pinned to the trailing edge, so it is the last one there.
      expect(layout.allColumns.last.column.field, 'name');
      expect(layout.trailing.single.width, greaterThan(140));
    });
  });

  group('cache keys come from each spec', () {
    test('a sort spec states every field that changes its result', () {
      const ascending = SortSpec('price');
      final descending = ascending.reversed;
      const nullsFirst = SortSpec('price', nulls: NullsPosition.first);
      expect(ascending.fingerprint, isNot(descending.fingerprint));
      expect(ascending.fingerprint, isNot(nullsFirst.fingerprint));
      expect(ascending.fingerprint, const SortSpec('price').fingerprint);
    });

    test(
        'two custom aggregations with one id but different reducers are not '
        'the same aggregate', () {
      final first = Aggregation(
        'price',
        type: AggregateType.custom,
        id: 'x',
        compute: sumValues,
      );
      final second = Aggregation(
        'price',
        type: AggregateType.custom,
        id: 'x',
        compute: countValues,
      );
      expect(first.fingerprint, isNot(second.fingerprint));
    });

    test('a query fingerprints each stage of the pipeline', () {
      const base = GridQuery(sorts: [SortSpec('price')], search: 'mo');
      // Changing the ordering leaves the matched set alone.
      final reordered = base.copyWith(sorts: [const SortSpec('name')]);
      expect(reordered.matchFingerprint, base.matchFingerprint);
      expect(reordered.orderFingerprint, isNot(base.orderFingerprint));

      // Changing the needle changes both.
      final searched = base.copyWith(search: 'mouse');
      expect(searched.matchFingerprint, isNot(base.matchFingerprint));

      // The needle is compared as matching uses it.
      expect(base.copyWith(search: ' MO ').matchFingerprint,
          base.matchFingerprint);
    });

    test('regrouping with a different keyOf misses the cache, as it must', () {
      const groups = GridQuery(groups: [GroupSpec('price')]);
      final other = GridQuery(
        groups: [GroupSpec('price', keyOf: odd)],
      );
      expect(other.groupFingerprint, isNot(groups.groupFingerprint));
    });

    test('aggregations are part of the group identity', () {
      const plain = GridQuery(groups: [GroupSpec('category')]);
      final withSum = plain.copyWith(
        aggregations: const [Aggregation.sum('price')],
      );
      expect(withSum.groupFingerprint, isNot(plain.groupFingerprint));
    });
  });

  group('capabilities instead of type checks', () {
    test(
        'a synchronous source that is not InMemoryDataSource still resolves '
        'in the constructor', () {
      final source = SyncSource(sampleProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
      );
      expect(grid.isLoading, isFalse);
      expect(grid.rowCount, 6);
      expect(source.asyncFetches, 0, reason: 'the sync path was taken');
    });

    test('a source that says nothing is treated as remote', () async {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: AsyncDataSource<Product>(
          (q) async =>
              GridResult<Product>(rows: sampleProducts(), totalCount: 6),
        ),
      );
      expect(grid.isLoading, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(grid.rowCount, 6);
    });

    test('fetchSync throws rather than lying about an empty result', () {
      final source = AsyncDataSource<Product>(
        (q) async => GridResult<Product>(rows: const [], totalCount: 0),
      );
      expect(source.isSynchronous, isFalse);
      expect(
        () => source.fetchSync(const GridQuery()),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('an in-memory source declares what it can do', () {
      final capabilities = productGrid().sourceCapabilities;
      expect(capabilities.isLocal, isTrue);
      expect(capabilities.isSynchronous, isTrue);
      expect(capabilities.canWrite, isTrue);
      expect(capabilities.providesStats, isTrue);
      expect(capabilities.providesDistinctValues, isTrue);
      expect(capabilities.supportsLazyGroups, isFalse);
      expect('$capabilities', contains('local'));
    });

    test('a bare async source claims nothing it cannot honour', () {
      final source = AsyncDataSource<Product>(
        (q) async => GridResult<Product>(rows: const [], totalCount: 0),
      );
      final capabilities = source.capabilities;
      expect(capabilities.isLocal, isFalse);
      expect(capabilities.canWrite, isFalse);
      expect(capabilities.providesStats, isFalse);
      expect(capabilities.supportsCancellation, isFalse);
    });
  });

  group('what changed', () {
    List<Set<GridChange>> recordOn(GridController<Product> grid) {
      final seen = <Set<GridChange>>[];
      grid.addChangeListener(seen.add);
      return seen;
    }

    test('clicking a cell does not say the rows changed', () {
      final grid = productGrid(selectionMode: SelectionMode.cellRange);
      final seen = recordOn(grid);
      grid.selectCell(const CellAddress(1, 'name'));
      expect(seen, [
        {GridChange.selection}
      ]);
      expect(seen.single.contains(GridChange.rows), isFalse);
    });

    test('resizing a column is layout, not rows', () {
      final grid = productGrid();
      final seen = recordOn(grid);
      grid.resizeColumn('name', 220);
      expect(seen.single, {GridChange.layout});
    });

    test('sorting changes the rows', () {
      final grid = productGrid();
      final seen = recordOn(grid);
      grid.toggleSort('price');
      expect(seen.single, contains(GridChange.rows));
      expect(seen.single.contains(GridChange.layout), isFalse);
    });

    test('an edit session is its own kind of change', () {
      final grid = productGrid();
      final seen = recordOn(grid);
      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('Keypad');
      expect(seen, [
        {GridChange.edit},
        {GridChange.edit},
      ]);
    });

    test('hiding a column reports both the geometry and the rows, once', () {
      final grid = productGrid();
      final seen = recordOn(grid);
      grid.setColumnVisible('category', false);
      expect(seen.length, 1, reason: 'batched into one notification');
      expect(seen.single, containsAll([GridChange.layout, GridChange.rows]));
    });

    test('a batch notifies once for the union of what it did', () {
      final grid = productGrid();
      final seen = recordOn(grid);
      grid.batch(() {
        grid.resizeColumn('name', 200);
        grid.selectRow(1);
      });
      expect(seen.length, 1);
      expect(seen.single, {GridChange.layout, GridChange.selection});
    });

    test('a plain listener can read what the notification was about', () {
      final grid = productGrid();
      final seen = <Set<GridChange>>[];
      grid.addListener(() => seen.add(grid.lastChanges));
      grid.clearSelection();
      grid.selectRow(0);
      expect(seen.last, {GridChange.selection});
    });

    test('a caller that says nothing means everything', () {
      final source = InMemoryDataSource<Product>(sampleProducts());
      final seen = <Set<GridChange>>[];
      source.addChangeListener(seen.add);
      // A source invalidating itself does not know what it affected.
      source.invalidate();
      expect(seen.single, everyGridChange);
    });

    test('the controller narrows a blanket notification from its source', () {
      final source = InMemoryDataSource<Product>(sampleProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
      );
      final seen = recordOn(grid);
      source.invalidate();
      // It re-queried, so it knows the rows are what changed - not the
      // column geometry, and not the edit session.
      expect(seen.single, contains(GridChange.rows));
      expect(seen.single.contains(GridChange.layout), isFalse);
      expect(seen.single.contains(GridChange.edit), isFalse);
    });

    test('removing a change listener stops it', () {
      final grid = productGrid();
      final seen = <Set<GridChange>>[];
      void listener(Set<GridChange> changes) => seen.add(changes);
      grid.addChangeListener(listener);
      grid.selectRow(0);
      grid.removeChangeListener(listener);
      grid.selectRow(1);
      expect(seen.length, 1);
    });
  });
}

Object? sumValues(List<Object?> values) => values.length;
Object? countValues(List<Object?> values) => values.length + 1;
Object? odd(Object? value) => (value as num) % 2 == 1;
