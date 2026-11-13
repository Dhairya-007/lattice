// The pipeline is memoised, so these tests exist to prove it can never serve
// a stale answer. Each one changes something the cache key has to notice.
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  InMemoryDataSource<Product> source([List<Product>? rows]) {
    return InMemoryDataSource<Product>(rows ?? sampleProducts())
      ..columns = productColumnMap();
  }

  List<String> namesOf(GridResult<Product> result) => [
        for (final row in result.rows) row.name,
      ];

  group('revision', () {
    test('starts at a known point and advances on every mutation', () {
      final data = source();
      final start = data.revision;
      data.add(Product(id: 7, name: 'Hub', category: 'Input', price: 30));
      expect(data.revision, greaterThan(start));
      final afterAdd = data.revision;
      data.removeAt(0);
      expect(data.revision, greaterThan(afterAdd));
    });

    test('does not advance when a mutator changed nothing', () {
      final data = source(<Product>[]);
      final start = data.revision;
      data.clear();
      data.removeWhere((p) => false);
      expect(data.revision, start);
    });

    test('advances when the columns are replaced', () {
      final data = source();
      final start = data.revision;
      data.columns = productColumnMap();
      expect(data.revision, greaterThan(start));
    });
  });

  group('stale results after a mutation', () {
    test('an added row appears in a repeated query', () {
      final data = source();
      const query = GridQuery(sorts: [SortSpec('name')]);
      expect(data.fetchSync(query).rows.length, 6);
      data.add(Product(id: 7, name: 'Aardvark', category: 'Input', price: 1));
      final again = data.fetchSync(query);
      expect(again.rows.length, 7);
      expect(again.rows.first.name, 'Aardvark');
    });

    test('a removed row disappears', () {
      final data = source();
      const query = GridQuery(sorts: [SortSpec('price')]);
      expect(namesOf(data.fetchSync(query)).first, 'Mouse');
      data.removeWhere((p) => p.name == 'Mouse');
      expect(namesOf(data.fetchSync(query)).first, 'Webcam');
    });

    test('an edited value is re-filtered and re-sorted', () {
      final rows = sampleProducts();
      final data = source(rows);
      const query = GridQuery(
        sorts: [SortSpec('price')],
        filter: FilterCondition(
          field: 'price',
          operator: FilterOperator.lessThan,
          value: 100,
        ),
      );
      expect(namesOf(data.fetchSync(query)), ['Mouse', 'Webcam', 'Keyboard']);

      rows[1].price = 5000;
      data.replaceAt(1, rows[1]);
      expect(namesOf(data.fetchSync(query)), ['Webcam', 'Keyboard']);
    });

    test('a search repeated after a mutation sees the new text', () {
      final rows = sampleProducts();
      final data = source(rows);
      const query = GridQuery(search: 'keyb');
      expect(data.fetchSync(query).rows.length, 1);

      rows[0].name = 'Trackpad';
      data.replaceAt(0, rows[0]);
      expect(data.fetchSync(query).rows, isEmpty);
    });

    test('a replaced formatter changes what search matches', () {
      final data = source();
      const query = GridQuery(search: 'usd');
      expect(data.fetchSync(query).rows.length, 6);

      final relabelled = {
        for (final entry in productColumnMap().entries)
          entry.key: entry.key == 'price'
              ? entry.value.copyWith(format: (v) => 'EUR $v')
              : entry.value,
      };
      data.columns = relabelled;
      expect(data.fetchSync(query).rows, isEmpty);
      expect(data.fetchSync(const GridQuery(search: 'eur')).rows.length, 6);
    });

    test('clearing the rows empties a cached query', () {
      final data = source();
      const query = GridQuery(sorts: [SortSpec('name')]);
      expect(data.fetchSync(query).rows, isNotEmpty);
      data.clear();
      expect(data.fetchSync(query).rows, isEmpty);
      expect(data.fetchSync(query).totalCount, 0);
    });
  });

  group('cached stages answer each query shape correctly', () {
    test('changing only the sort direction reverses the same rows', () {
      final data = source();
      final ascending = namesOf(
        data.fetchSync(const GridQuery(sorts: [SortSpec('price')])),
      );
      final descending = namesOf(
        data.fetchSync(
          const GridQuery(
            sorts: [
              SortSpec('price', direction: SortDirection.descending),
            ],
          ),
        ),
      );
      expect(descending, ascending.reversed.toList());
    });

    test('changing only the page re-slices the same ordering', () {
      final data = source();
      final all = namesOf(
        data.fetchSync(const GridQuery(sorts: [SortSpec('price')])),
      );
      final second = namesOf(
        data.fetchSync(
          const GridQuery(sorts: [SortSpec('price')], offset: 2, limit: 2),
        ),
      );
      expect(second, all.sublist(2, 4));
    });

    test('null placement is still honoured through the cache', () {
      final data = source();
      const last = GridQuery(sorts: [SortSpec('stock')]);
      const first = GridQuery(
        sorts: [SortSpec('stock', nulls: NullsPosition.first)],
      );
      expect(data.fetchSync(last).rows.last.stock, isNull);
      expect(data.fetchSync(first).rows.first.stock, isNull);
      expect(data.fetchSync(last).rows.last.stock, isNull);
    });

    test('adding a filter to a cached search narrows it further', () {
      final data = source();
      expect(data.fetchSync(const GridQuery(search: 'o')).rows.length, 5);
      final narrowed = data.fetchSync(
        const GridQuery(
          search: 'o',
          filter: FilterCondition(
            field: 'category',
            operator: FilterOperator.equals,
            value: 'Compute',
          ),
        ),
      );
      expect(namesOf(narrowed), ['Laptop', 'Dock']);
    });

    test('aggregates track the current filter, not a previous one', () {
      final data = source();
      const all = GridQuery(aggregations: [Aggregation.sum('price')]);
      const input = GridQuery(
        aggregations: [Aggregation.sum('price')],
        filter: FilterCondition(
          field: 'category',
          operator: FilterOperator.equals,
          value: 'Input',
        ),
      );
      expect(data.fetchSync(all).aggregates['price.sum'], 2115);
      expect(data.fetchSync(input).aggregates['price.sum'], 165);
      expect(data.fetchSync(all).aggregates['price.sum'], 2115);
    });

    test('order-sensitive aggregates follow the current sort', () {
      final data = source();
      const first = Aggregation(
        'name',
        type: AggregateType.first,
        id: 'firstName',
      );
      expect(
        data
            .fetchSync(
              const GridQuery(
                  sorts: [SortSpec('price')], aggregations: [first]),
            )
            .aggregates['firstName'],
        'Mouse',
      );
      expect(
        data
            .fetchSync(
              const GridQuery(
                sorts: [
                  SortSpec('price', direction: SortDirection.descending),
                ],
                aggregations: [first],
              ),
            )
            .aggregates['firstName'],
        'Laptop',
      );
    });

    test('changing the group field regroups', () {
      final data = source();
      final byCategory = data.fetchSync(
        const GridQuery(groups: [GroupSpec('category')]),
      );
      expect(byCategory.groups.length, 3);
      final byActive = data.fetchSync(
        const GridQuery(groups: [GroupSpec('active')]),
      );
      expect(byActive.groups.length, 2);
      expect(
        data
            .fetchSync(const GridQuery(groups: [GroupSpec('category')]))
            .groups
            .length,
        3,
      );
    });
  });

  group('incremental search', () {
    test('typing forward matches a one-shot search exactly', () {
      final data = source();
      final typed = <int>[];
      for (final needle in ['k', 'ke', 'key', 'keyb']) {
        typed.add(data.fetchSync(GridQuery(search: needle)).rows.length);
      }
      final fresh = source();
      expect(
        typed,
        [
          for (final needle in ['k', 'ke', 'key', 'keyb'])
            fresh.fetchSync(GridQuery(search: needle)).rows.length,
        ],
      );
      expect(typed.last, 1);
    });

    test('backspacing widens the result again', () {
      final data = source();
      expect(data.fetchSync(const GridQuery(search: 'keyb')).rows.length, 1);
      expect(data.fetchSync(const GridQuery(search: 'key')).rows.length, 1);
      // 'k' is in Keyboard and Dock, and nowhere else in the sample.
      expect(data.fetchSync(const GridQuery(search: 'k')).rows.length, 2);
      expect(data.fetchSync(const GridQuery(search: '')).rows.length, 6);
    });

    test('clearing and retyping gives the same answer', () {
      final data = source();
      final once = data.fetchSync(const GridQuery(search: 'mo')).rows.length;
      data.fetchSync(const GridQuery(search: ''));
      final twice = data.fetchSync(const GridQuery(search: 'mo')).rows.length;
      expect(twice, once);
      expect(twice, 2);
    });

    test('a needle cannot match text spanning two columns', () {
      // 'Keyboard' then 'Input' are adjacent in the row, and the index joins
      // columns with a character a user cannot type.
      final data = source();
      expect(
        data.fetchSync(const GridQuery(search: 'keyboardinput')).rows,
        isEmpty,
      );
      expect(
          data.fetchSync(const GridQuery(search: 'keyboard')).rows.length, 1);
    });

    test('search narrows within an unchanged filter', () {
      final data = source();
      const filter = FilterCondition(
        field: 'category',
        operator: FilterOperator.equals,
        value: 'Input',
      );
      expect(
        data.fetchSync(const GridQuery(filter: filter)).rows.length,
        3,
      );
      expect(
        namesOf(data.fetchSync(const GridQuery(filter: filter, search: 'm'))),
        ['Mouse', 'Webcam'],
      );
      expect(
        namesOf(data.fetchSync(const GridQuery(filter: filter, search: 'mo'))),
        ['Mouse'],
      );
    });

    test('changing the filter under a search re-evaluates both', () {
      final data = source();
      expect(
        data
            .fetchSync(
              const GridQuery(
                search: 'o',
                filter: FilterCondition(
                  field: 'category',
                  operator: FilterOperator.equals,
                  value: 'Input',
                ),
              ),
            )
            .rows
            .length,
        2,
      );
      expect(
        namesOf(
          data.fetchSync(
            const GridQuery(
              search: 'o',
              filter: FilterCondition(
                field: 'category',
                operator: FilterOperator.equals,
                value: 'Compute',
              ),
            ),
          ),
        ),
        ['Laptop', 'Dock'],
      );
    });

    test('search is restricted to the fields asked for', () {
      final data = source();
      expect(
        data
            .fetchSync(
              const GridQuery(search: 'input', searchFields: ['name']),
            )
            .rows,
        isEmpty,
      );
      expect(
        data
            .fetchSync(
              const GridQuery(search: 'input', searchFields: ['category']),
            )
            .rows
            .length,
        3,
      );
    });
  });

  group('LazyDataRowList', () {
    test('materialises rows on read with the right indices', () {
      final grid = productGrid();
      expect(grid.visibleRows.length, 6);
      final row = grid.visibleRows[3] as DataGridRow<Product>;
      expect(row.index, 3);
      expect(row.sourceIndex, 3);
      expect(row.data.name, 'Laptop');
    });

    test('carries the page offset into sourceIndex', () {
      final grid = productGrid(pageSize: 2);
      grid.goToPage(2);
      final row = grid.visibleRows.first as DataGridRow<Product>;
      expect(row.index, 0);
      expect(row.sourceIndex, 4);
    });

    test('is read-only', () {
      final grid = productGrid();
      final placeholder = GroupGridRow<Product>(
        index: 0,
        depth: 0,
        node: GroupNode<Product>(
          field: 'category',
          key: 'x',
          label: 'x',
          depth: 0,
          path: 'x',
        ),
        expanded: true,
      );
      expect(() => grid.visibleRows.add(placeholder), throwsUnsupportedError);
      expect(() => grid.visibleRows.clear(), throwsUnsupportedError);
    });

    test('iterates every row in order', () {
      final grid = productGrid(sorts: [const SortSpec('name')]);
      expect(
        grid.visibleRows
            .cast<DataGridRow<Product>>()
            .map((r) => r.data.name)
            .toList(),
        ['Dock', 'Keyboard', 'Laptop', 'Monitor', 'Mouse', 'Webcam'],
      );
    });

    test('a grouped grid still materialises its rows eagerly', () {
      final grid = productGrid(groups: [const GroupSpec('category')]);
      expect(grid.visibleRows.first, isA<GroupGridRow<Product>>());
      expect(grid.visibleRows.length, 9);
    });
  });
}
