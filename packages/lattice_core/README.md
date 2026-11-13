# lattice_core

The data grid engine behind [Lattice](https://github.com/Dhairya-007/lattice),
in pure Dart. No Flutter dependency, no UI toolkit of any kind.

Everything a data grid does other than paint lives here:

| Area | What it covers |
| --- | --- |
| Columns | typed accessors, formatters, comparators, width bounds, pinning, visibility, edit hooks |
| Sorting | multi-column, stable, custom comparators, explicit null placement |
| Filtering | a serialisable condition/group tree, 16 operators, free-text search |
| Grouping | nested levels, derived keys, path-keyed expansion state |
| Aggregation | sum, average, min, max, count, distinct count, custom reducers |
| Virtualization | uniform and variable row heights, scroll-to-reveal, column windowing |
| Layout | leading / scrolling / trailing panes, stretch and last-column fit |
| Selection | single and multi row, single cell, rectangular ranges, ctrl / shift semantics |
| Editing | validated edit sessions with commit and rollback |
| Export | RFC 4180 CSV, grouped CSV, tab-separated clipboard text |

## Why a separate package

Two reasons.

The first is testability. Grid behaviour is where grids actually go wrong — a
sort that is not stable, a filter row that hides every row while half-typed, an
expansion state that resets when the data reloads, a stale async response that
overwrites a newer one. All of that is plain Dart here, so it is covered by fast
unit tests rather than widget tests that need a pumped frame to assert anything.

The second is reach. A UI adapter is a thin shell over `GridController`:
listen for changes, read `visibleRows`, call methods from gestures. Flutter is
the first adapter; the same engine is meant to drive the web ones.

## Use

```dart
final controller = GridController<Employee>(
  columns: [
    GridColumn(field: 'name', value: (e) => e.name, pin: ColumnPin.start),
    GridColumn(
      field: 'salary',
      type: ColumnType.number,
      value: (e) => e.salary,
      format: (v) => NumberFormat.currency().format(v),
      setValue: (e, v) => e.copyWith(salary: v! as num),
      validator: numberRange(min: 0),
    ),
    GridColumn(field: 'department', value: (e) => e.department),
  ],
  dataSource: InMemoryDataSource(employees),
  sorts: const [SortSpec('name')],
  aggregations: const [Aggregation.sum('salary')],
);

controller.groupBy('department');
controller.setSearch('engineering');
controller.toggleSort('salary', additive: true);

for (final row in controller.visibleRows) {
  switch (row) {
    case DataGridRow<Employee>(:final data):
      print(data.name);
    case GroupGridRow<Employee>(:final label, :final rowCount):
      print('$label ($rowCount)');
  }
}
```

### A remote source

`GridQuery` carries everything the view implies — sorts, filters, search,
grouping, aggregates, offset and limit — so a server-backed grid only has to
translate it:

```dart
final source = AsyncDataSource<Employee>((query) async {
  final response = await api.get('/employees', query: {
    'sort': query.sorts.map((s) => '${s.field}:${s.direction.name}').join(','),
    'filter': jsonEncode(query.filter?.toJson()),
    'offset': query.offset,
    'limit': query.limit,
  });
  return GridResult(
    rows: response.rows.map(Employee.fromJson).toList(),
    totalCount: response.total,
  );
});
```

Concurrent fetches are token-guarded by the controller, so a slow response from
an earlier query can never overwrite a newer one.

## Performance notes

- `InMemoryDataSource` runs the whole pipeline eagerly on each query. Around
  100k rows that stays inside a frame budget on a desktop machine; past that,
  push the work into a database behind an `AsyncDataSource`.
- Row offsets are a prefix-sum table with binary-searched lookups, so scrolling
  a million variable-height rows is O(log n) per frame rather than O(n).
- Filtering projects only the fields a filter actually references, so filtering
  a wide table does not build a full map per row.

## Licence

MIT.
