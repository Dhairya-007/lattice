import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  InMemoryDataSource<Product> source([List<Product>? rows]) {
    return InMemoryDataSource<Product>(rows ?? sampleProducts())
      ..columns = productColumnMap();
  }

  group('pipeline', () {
    test('returns every row for an empty query', () {
      final result = source().fetchSync(const GridQuery());
      expect(result.rows.length, 6);
      expect(result.totalCount, 6);
      expect(result.matchedCount, 6);
    });

    test('filters, and reports matched against total', () {
      final result = source().fetchSync(const GridQuery(
        filter: FilterCondition(
          field: 'category',
          operator: FilterOperator.equals,
          value: 'Input',
        ),
      ));
      expect(result.rows.length, 3);
      expect(result.matchedCount, 3);
      expect(result.totalCount, 6);
    });

    test('sorts after filtering', () {
      final result = source().fetchSync(const GridQuery(
        filter: FilterCondition(
          field: 'category',
          operator: FilterOperator.equals,
          value: 'Input',
        ),
        sorts: [SortSpec('price')],
      ));
      expect(result.rows.map((p) => p.name), ['Mouse', 'Webcam', 'Keyboard']);
    });

    test('search matches on displayed text across visible columns', () {
      final result = source().fetchSync(const GridQuery(search: 'input'));
      expect(result.rows.length, 3);
    });

    test('search is case-insensitive and respects column formatters', () {
      expect(
        source().fetchSync(const GridQuery(search: 'USD')).rows.length,
        6,
      );
      expect(
        source().fetchSync(const GridQuery(search: 'KEYBOARD')).rows.length,
        1,
      );
    });

    test('search can be narrowed to given fields', () {
      final result = source().fetchSync(const GridQuery(
        search: 'Input',
        searchFields: ['name'],
      ));
      expect(result.rows, isEmpty);
    });

    test('blank search matches everything', () {
      expect(source().fetchSync(const GridQuery(search: '   ')).rows.length, 6);
    });

    test('an unfilled filter condition does not hide rows', () {
      final result = source().fetchSync(const GridQuery(
        filter: FilterCondition(
          field: 'name',
          operator: FilterOperator.contains,
        ),
      ));
      expect(result.rows.length, 6);
    });
  });

  group('paging', () {
    test('offset and limit slice the sorted result', () {
      final result = source().fetchSync(const GridQuery(
        sorts: [SortSpec('price')],
        offset: 2,
        limit: 2,
      ));
      expect(result.rows.map((p) => p.name), ['Keyboard', 'Dock']);
      expect(result.matchedCount, 6);
    });

    test('a page past the end comes back empty rather than throwing', () {
      final result =
          source().fetchSync(const GridQuery(offset: 100, limit: 10));
      expect(result.rows, isEmpty);
      expect(result.matchedCount, 6);
    });

    test('a limit longer than the data returns what there is', () {
      expect(
        source().fetchSync(const GridQuery(limit: 100)).rows.length,
        6,
      );
    });

    test('paging counts filtered rows, not all rows', () {
      final result = source().fetchSync(const GridQuery(
        search: 'Input',
        limit: 2,
      ));
      expect(result.rows.length, 2);
      expect(result.matchedCount, 3);
      expect(result.totalCount, 6);
    });
  });

  group('grouping and aggregates', () {
    test('a grouped query returns a tree and no flat rows', () {
      final result = source().fetchSync(const GridQuery(
        groups: [GroupSpec('category')],
      ));
      expect(result.isGrouped, isTrue);
      expect(result.rows, isEmpty);
      expect(result.groups.length, 3);
    });

    test('grouping ignores paging so group counts stay whole', () {
      final result = source().fetchSync(const GridQuery(
        groups: [GroupSpec('category')],
        limit: 2,
      ));
      expect(
        result.groups.fold<int>(0, (sum, g) => sum + g.rowCount),
        6,
      );
    });

    test('grid-wide aggregates cover the filtered set, not the page', () {
      final result = source().fetchSync(const GridQuery(
        aggregations: [Aggregation.sum('price')],
        limit: 1,
      ));
      expect(result.rows.length, 1);
      expect(result.aggregates['price.sum'], 2115);
    });

    test('aggregates follow the filter', () {
      final result = source().fetchSync(const GridQuery(
        search: 'Input',
        aggregations: [Aggregation.sum('price')],
      ));
      expect(result.aggregates['price.sum'], 165);
    });
  });

  group('mutation and notification', () {
    test('mutators notify listeners', () {
      final data = source();
      var notifications = 0;
      data.addListener(() => notifications++);

      data.add(Product(id: 7, name: 'Hub', category: 'Input', price: 30));
      data.addAll([Product(id: 8, name: 'Pad', category: 'Input', price: 5)]);
      data.insert(
          0, Product(id: 9, name: 'Cable', category: 'Input', price: 9));
      data.removeAt(0);
      data.setRows(sampleProducts());
      data.clear();
      expect(notifications, 6);
      expect(data.length, 0);
    });

    test('clearing an empty source does not notify', () {
      final data = source(<Product>[]);
      var notifications = 0;
      data.addListener(() => notifications++);
      data.clear();
      expect(notifications, 0);
    });

    test('removeWhere notifies only when something was removed', () {
      final data = source();
      var notifications = 0;
      data.addListener(() => notifications++);
      data.removeWhere((p) => p.category == 'Nothing');
      expect(notifications, 0);
      data.removeWhere((p) => p.category == 'Input');
      expect(notifications, 1);
      expect(data.length, 3);
    });

    test('replaceAt swaps a row in place', () {
      final data = source();
      data.replaceAt(
          0, Product(id: 99, name: 'Swapped', category: 'X', price: 1));
      expect(data.rows.first.name, 'Swapped');
      expect(data.length, 6);
    });

    test('the exposed row list cannot be mutated from outside', () {
      expect(
        () => source().rows.add(
              Product(id: 1, name: 'x', category: 'y', price: 0),
            ),
        throwsUnsupportedError,
      );
    });

    test('a batch collapses many changes into one notification', () {
      final data = source();
      var notifications = 0;
      data.addListener(() => notifications++);
      data.batch(() {
        data.add(Product(id: 7, name: 'a', category: 'x', price: 1));
        data.add(Product(id: 8, name: 'b', category: 'x', price: 1));
        data.add(Product(id: 9, name: 'c', category: 'x', price: 1));
      });
      expect(notifications, 1);
      expect(data.length, 9);
    });

    test('a removed listener stops hearing about changes', () {
      final data = source();
      var notifications = 0;
      void listener() => notifications++;
      data.addListener(listener);
      data.removeListener(listener);
      data.add(Product(id: 7, name: 'a', category: 'x', price: 1));
      expect(notifications, 0);
    });

    test('using a disposed source is an error, not silent breakage', () {
      final data = source();
      data.dispose();
      expect(data.isDisposed, isTrue);
      expect(() => data.addListener(() {}), throwsStateError);
    });
  });

  group('AsyncDataSource', () {
    test('passes the query through and returns what the callback gives',
        () async {
      GridQuery? seen;
      final data = AsyncDataSource<Product>((query) async {
        seen = query;
        return GridResult<Product>(rows: sampleProducts(), totalCount: 6);
      });
      final result = await data.fetch(const GridQuery(search: 'abc'));
      expect(seen!.search, 'abc');
      expect(result.rows.length, 6);
      expect(data.isLocal, isFalse);
    });
  });

  group('GridQuery', () {
    test('copyWith replaces only what it is given', () {
      const query =
          GridQuery(search: 'a', sorts: [SortSpec('name')], limit: 10);
      final next = query.copyWith(search: 'b');
      expect(next.search, 'b');
      expect(next.sorts, query.sorts);
      expect(next.limit, 10);
    });

    test('copyWith can clear the filter and the limit', () {
      const query = GridQuery(
        filter: FilterCondition(
          field: 'name',
          operator: FilterOperator.contains,
          value: 'a',
        ),
        limit: 10,
      );
      final next = query.copyWith(clearFilter: true, clearLimit: true);
      expect(next.filter, isNull);
      expect(next.limit, isNull);
      expect(next.isPaged, isFalse);
    });

    test('serialises only the parts that are set', () {
      expect(const GridQuery().toJson(), isEmpty);
      final json = const GridQuery(
        sorts: [SortSpec('name')],
        search: 'abc',
        limit: 25,
      ).toJson();
      expect(json.keys, containsAll(['sorts', 'search', 'limit']));
      expect(json.containsKey('filter'), isFalse);
    });
  });
}
