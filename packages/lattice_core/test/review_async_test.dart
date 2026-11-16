// Async lifecycle fixes from the 0.4.0 review: futures that never completed,
// a spinner that never stopped, and state that outlived its query.
import 'dart:async';

import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

class _SlowSource extends LatticeDataSource<Product> {
  _SlowSource(this.delay);

  final Duration delay;
  int fetches = 0;

  @override
  Future<GridResult<Product>> fetch(GridQuery query) async {
    fetches++;
    await Future<void>.delayed(delay);
    return GridResult<Product>(
      rows: sampleProducts(),
      totalCount: sampleProducts().length,
    );
  }
}

/// A source that maps its own aborted request onto [FetchCancelled], which is
/// what an HTTP client's abort looks like from the outside.
class _SelfCancellingSource extends LatticeDataSource<Product> {
  @override
  Future<GridResult<Product>> fetch(GridQuery query) async {
    await Future<void>.delayed(Duration.zero);
    throw const FetchCancelled('the connection was aborted');
  }
}

class _FailingSource extends LatticeDataSource<Product> {
  _FailingSource();

  bool fail = false;

  @override
  Future<GridResult<Product>> fetch(GridQuery query) async {
    await Future<void>.delayed(Duration.zero);
    if (fail) throw StateError('no');
    return GridResult<Product>(
      rows: sampleProducts(),
      totalCount: sampleProducts().length,
      filteredCount: sampleProducts().length,
    );
  }
}

void main() {
  group('a debounced refresh', () {
    test('completes when the grid is disposed', () async {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: _SlowSource(Duration.zero),
        fetchDebounce: const Duration(seconds: 10),
      );
      final pending = grid.refresh(coalesce: true);
      grid.dispose();
      // Without this, the caller waits for the life of the isolate.
      await pending.timeout(const Duration(seconds: 1));
    });

    test('completes when a direct refresh overtakes it', () async {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: _SlowSource(Duration.zero),
        fetchDebounce: const Duration(seconds: 10),
      );
      final coalesced = grid.refresh(coalesce: true);
      await grid.refresh();
      await coalesced.timeout(const Duration(seconds: 1));
      grid.dispose();
    });
  });

  group('a FetchCancelled the grid did not ask for', () {
    test('stops the spinner and surfaces the error', () async {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: _SelfCancellingSource(),
      );
      await grid.refresh();
      expect(grid.isLoading, isFalse);
      expect(grid.error, isA<FetchCancelled>());
      grid.dispose();
    });
  });

  group('after a failed fetch', () {
    test('the counts do not describe rows that are gone', () async {
      final source = _FailingSource();
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
      );
      await grid.refresh();
      expect(grid.matchedCount, sampleProducts().length);

      source.fail = true;
      await grid.refresh();
      expect(grid.rowCount, 0);
      expect(grid.matchedCount, 0, reason: 'the footer must not lie');
      expect(grid.totalCount, 0);
      expect(grid.isStale, isFalse);
      grid.dispose();
    });

    test('keepRowsOnError keeps the rows and says they are stale', () async {
      final source = _FailingSource();
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        keepRowsOnError: true,
      );
      await grid.refresh();
      source.fail = true;
      await grid.refresh();
      expect(grid.rowCount, greaterThan(0));
      expect(grid.isStale, isTrue);
      grid.dispose();
    });
  });

  group('paging', () {
    test('clamps the page when the data shrinks under it', () {
      final source = InMemoryDataSource<Product>(sampleProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        pageSize: 2,
      );
      grid.goToPage(grid.pageCount - 1);
      final lastPage = grid.pageIndex;
      expect(lastPage, greaterThan(0));

      source.setRows([sampleProducts().first]);
      expect(grid.pageCount, 1);
      expect(grid.pageIndex, 0);
      expect(grid.rowCount, 1, reason: 'rows exist, so rows must be shown');
      grid.dispose();
    });

    test('a grouped grid reports the one page it can turn', () {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(sampleProducts()),
        pageSize: 2,
        groups: const [GroupSpec('category')],
      );
      expect(grid.pageCount, 1);
      expect(grid.hasNextPage, isFalse);
      grid.dispose();
    });
  });
}
