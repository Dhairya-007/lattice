import 'dart:async';

import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Records the queries it is asked for and whether each one was cancelled.
class RecordingSource extends LatticeDataSource<Product> {
  RecordingSource({this.delay = Duration.zero});

  final Duration delay;
  final List<String> searches = [];
  final List<FetchSignal> signals = [];
  int aborted = 0;

  @override
  Future<GridResult<Product>> fetch(GridQuery query) async {
    searches.add(query.search);
    final signal = query.signal;
    if (signal != null) signals.add(signal);
    await Future<void>.delayed(delay);
    if (signal != null && signal.isCancelled) {
      aborted++;
      throw FetchCancelled(signal.reason);
    }
    return GridResult<Product>(
      rows: sampleProducts(),
      totalCount: sampleProducts().length,
    );
  }
}

void main() {
  group('FetchSignal', () {
    test('cancelling runs the listeners once and only once', () {
      final signal = FetchSignal();
      var calls = 0;
      signal.onCancel(() => calls++);
      signal.cancel();
      signal.cancel();
      expect(calls, 1);
      expect(signal.isCancelled, isTrue);
    });

    test('a listener added after cancellation runs immediately', () {
      final signal = FetchSignal()..cancel('gone');
      var called = false;
      signal.onCancel(() => called = true);
      expect(called, isTrue);
      expect(signal.reason, 'gone');
    });

    test('throwIfCancelled is the bail-out for work a source does itself', () {
      final signal = FetchSignal();
      expect(signal.throwIfCancelled, returnsNormally);
      signal.cancel();
      expect(signal.throwIfCancelled, throwsA(isA<FetchCancelled>()));
    });

    test('whenCancelled completes, before or after the fact', () async {
      final early = FetchSignal();
      final waiting = early.whenCancelled;
      early.cancel();
      await waiting;

      final late = FetchSignal()..cancel();
      await late.whenCancelled;
    });

    test('the signal is left out of the query JSON', () {
      final query = GridQuery(search: 'x', signal: FetchSignal());
      expect(query.toJson().containsKey('signal'), isFalse);
      expect(query.copyWith(search: 'y').signal, isNotNull);
    });
  });

  group('cancellation', () {
    test('a superseded fetch is told to stop', () async {
      final source = RecordingSource(delay: const Duration(milliseconds: 20));
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
      );
      grid.setSearch('a');
      grid.setSearch('ab');
      await grid.refresh();

      expect(source.signals.first.isCancelled, isTrue);
      expect(source.signals.last.isCancelled, isFalse);
      expect(source.aborted, greaterThan(0));
      expect(grid.error, isNull, reason: 'cancellation is not a failure');
      expect(grid.rowCount, 6);
    });

    test('disposing cancels whatever is in flight', () async {
      final source = RecordingSource(delay: const Duration(milliseconds: 10));
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
      );
      grid.dispose();
      expect(source.signals.single.isCancelled, isTrue);
    });
  });

  group('debounce', () {
    test('a word typed into the search box sends one request', () async {
      final source = RecordingSource();
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        fetchDebounce: const Duration(milliseconds: 20),
      );
      await Future<void>.delayed(Duration.zero);
      source.searches.clear();

      for (final text in ['m', 'mo', 'mou', 'mous', 'mouse']) {
        grid.setSearch(text);
      }
      expect(grid.isFetchPending, isTrue);
      expect(source.searches, isEmpty);

      grid.setSearch('mouse!');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(source.searches, ['mouse!']);
      expect(grid.isFetchPending, isFalse);
    });

    test('the future a debounced refresh returns completes with the fetch',
        () async {
      final source = RecordingSource();
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        fetchDebounce: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(Duration.zero);
      source.searches.clear();

      final first = grid.refresh(coalesce: true);
      final second = grid.refresh(coalesce: true);
      await Future.wait([first, second]);
      expect(source.searches.length, 1);
    });

    test('a filter-row change is debounced too', () async {
      final source = RecordingSource();
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        fetchDebounce: const Duration(milliseconds: 20),
      );
      await Future<void>.delayed(Duration.zero);
      source.searches.clear();

      grid.setColumnFilter(
        'name',
        const FilterCondition(
          field: 'name',
          operator: FilterOperator.contains,
          value: 'mo',
        ),
      );
      expect(source.searches, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(source.searches.length, 1);
    });

    test('a local source is never debounced: it answers in the frame', () {
      final grid = productGrid()..fetchDebounce = const Duration(seconds: 5);
      grid.setSearch('mouse');
      expect(grid.isFetchPending, isFalse);
      expect(grid.rowCount, 1);
    });

    test('a pending debounce is dropped when the grid is disposed', () async {
      final source = RecordingSource();
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        fetchDebounce: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(Duration.zero);
      source.searches.clear();
      grid.setSearch('x');
      grid.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(source.searches, isEmpty);
    });
  });

  group('keepRowsOnError', () {
    test('off, a failed fetch empties the grid', () async {
      var fail = false;
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: AsyncDataSource<Product>((q) async {
          if (fail) throw StateError('offline');
          return GridResult<Product>(
            rows: sampleProducts(),
            totalCount: 6,
          );
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(grid.rowCount, 6);
      fail = true;
      await grid.refresh();
      expect(grid.rowCount, 0);
      expect(grid.error, isA<StateError>());
    });

    test('on, the last good rows stay on screen beside the error', () async {
      var fail = false;
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: AsyncDataSource<Product>((q) async {
          if (fail) throw StateError('offline');
          return GridResult<Product>(
            rows: sampleProducts(),
            totalCount: 6,
          );
        }),
        keepRowsOnError: true,
      );
      await Future<void>.delayed(Duration.zero);
      fail = true;
      await grid.refresh();
      expect(grid.rowCount, 6);
      expect(grid.error, isA<StateError>());
    });
  });
}
