import 'dart:convert';

import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Round-trips a view through text, the way an app's storage would.
GridViewState throughJson(GridViewState state) => GridViewState.fromJson(
      (jsonDecode(jsonEncode(state.toJson())) as Map).cast<String, Object?>(),
    );

void main() {
  group('a saved view', () {
    test('remembers everything the user arranged', () {
      final grid = productGrid();
      grid.toggleSort('price');
      grid.setSearch('o');
      grid.setColumnFilter(
        'category',
        const FilterCondition(
          field: 'category',
          operator: FilterOperator.equals,
          value: 'Input',
        ),
      );
      grid.resizeColumn('name', 260);
      grid.moveColumn('name', 3);
      grid.setColumnVisible('active', false);
      grid.setColumnPin('price', ColumnPin.start);
      grid.setPageSize(1);
      grid.goToPage(1);
      grid.columnFit = ColumnFit.stretch;
      grid.frozenRowCount = 1;

      final restoredInto = productGrid();
      restoredInto.restoreState(throughJson(grid.saveState()));

      expect(restoredInto.sorts, grid.sorts);
      expect(restoredInto.search, 'o');
      expect(restoredInto.columnFilters.keys, ['category']);
      expect(restoredInto.widthOf('name'), 260);
      expect(restoredInto.columns.map((c) => c.field), [
        'category',
        'price',
        'stock',
        'name',
        'active',
      ]);
      expect(restoredInto.column('active')!.visible, isFalse);
      expect(restoredInto.column('price')!.pin, ColumnPin.start);
      expect(restoredInto.pageSize, 1);
      expect(restoredInto.pageIndex, 1);
      expect(restoredInto.columnFit, ColumnFit.stretch);
      expect(restoredInto.frozenRowCount, 1);
      expect(labelsOf(restoredInto), labelsOf(grid));
    });

    test('does not record a width the user never dragged', () {
      final state = productGrid().saveState();
      expect(
        state.columns.every((c) => c.width == null),
        isTrue,
      );
      expect(state.toJson().containsKey('columns'), isTrue);
    });

    test('remembers which groups were closed, not which existed', () {
      final grid = productGrid(groups: [const GroupSpec('category')]);
      grid.toggleGroup('Input');
      final state = throughJson(grid.saveState());
      expect(state.collapsedGroupPaths, ['Input']);

      final restored = productGrid();
      restored.restoreState(state);
      final input = restored.visibleRows
          .whereType<GroupGridRow<Product>>()
          .firstWhere((r) => r.label == 'Input');
      expect(input.expanded, isFalse);
    });

    test('a grouping with a keyOf is restored through resolveGroup', () {
      final grid = productGrid(groups: [
        GroupSpec('price', keyOf: dear, labelOf: dearLabel),
      ]);
      final state = throughJson(grid.saveState());
      expect(state.groups.single.field, 'price');
      expect(state.groups.single.keyOf, isNull,
          reason: 'a function cannot be serialised');

      final restored = productGrid();
      restored.restoreState(
        state,
        resolveGroup: (g) =>
            g.field == 'price' ? g.restore(keyOf: dear, labelOf: dearLabel) : g,
      );
      expect(
        [
          for (final row in restored.visibleRows)
            if (row is GroupGridRow<Product>) row.label,
        ],
        ['cheap', 'dear'],
      );
    });

    test('queries once, however much it changes', () async {
      var fetches = 0;
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: AsyncDataSource<Product>((query) async {
          fetches++;
          return GridResult<Product>(rows: sampleProducts(), totalCount: 6);
        }),
      );
      await Future<void>.delayed(Duration.zero);
      fetches = 0;

      final source = productGrid();
      source.toggleSort('price');
      source.setSearch('o');
      source.setPageSize(2);
      grid.restoreState(source.saveState());
      await Future<void>.delayed(Duration.zero);
      expect(fetches, 1);
    });
  });

  group('restoring onto a grid whose columns have changed', () {
    test('ignores a column the grid no longer has', () {
      final state = GridViewState.fromJson({
        'columns': [
          {'field': 'gone'},
          {'field': 'price', 'width': 200.0},
        ],
      });
      final grid = productGrid();
      grid.restoreState(state);
      expect(grid.column('gone'), isNull);
      expect(grid.widthOf('price'), 200);
      expect(grid.columns.length, 5);
    });

    test('puts a column the view never saw after the ones it did', () {
      final old = productGrid();
      old.setColumns([
        for (final c in old.columns)
          if (c.field != 'active') c,
      ]);
      final grid = productGrid();
      grid.restoreState(old.saveState());
      expect(grid.columns.last.field, 'active');
    });
  });

  group('GridQuery.fromJson', () {
    test('round-trips the ordering, filter, search and paging', () {
      final grid = productGrid(pageSize: 2);
      grid.toggleSort('price');
      grid.setSearch('o');
      grid.goToPage(1);
      final json = grid.query.toJson();
      final query = GridQuery.fromJson(json);

      expect(query.sorts, grid.query.sorts);
      expect(query.search, 'o');
      expect(query.offset, 2);
      expect(query.limit, 2);
      expect(query.searchFields, grid.query.searchFields);
    });

    test('takes aggregations back as code, since they carry functions', () {
      final query = GridQuery.fromJson(
        const GridQuery(groups: [GroupSpec('category')]).toJson(),
        aggregations: const [Aggregation.sum('price')],
      );
      expect(query.groups.single.field, 'category');
      expect(query.aggregations.single.field, 'price');
    });

    test('an empty object is an empty query, not an error', () {
      final query = GridQuery.fromJson(const {});
      expect(query.sorts, isEmpty);
      expect(query.filter, isNull);
      expect(query.limit, isNull);
    });

    test('a filter tree survives the round trip', () {
      const filter = FilterGroup.or([
        FilterCondition(
          field: 'name',
          operator: FilterOperator.startsWith,
          value: 'M',
        ),
        FilterCondition(
          field: 'price',
          operator: FilterOperator.greaterThan,
          value: 100,
        ),
      ]);
      final query =
          GridQuery.fromJson(const GridQuery(filter: filter).toJson());
      expect(query.filter!.fingerprint, filter.fingerprint);
    });
  });
}

Object? dear(Object? value) => (value as num) > 100 ? 'dear' : 'cheap';
String dearLabel(Object? key) => '$key';
