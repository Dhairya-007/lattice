# lattice_core

The data grid engine behind [Lattice](https://github.com/Dhairya-007/lattice),
in pure Dart. No Flutter dependency, no UI toolkit of any kind.

Everything a data grid does other than paint lives here:

| Area | What it covers |
| --- | --- |
| Columns | typed accessors, formatters, comparators, width bounds, pinning, visibility, edit hooks |
| Sorting | multi-column, stable, custom comparators, explicit null placement |
| Filtering | a serialisable condition/group tree, 16 operators, free-text search |
| Grouping | nested levels, derived keys, path-keyed expansion, server-side and lazy |
| Tree data | parent/child rows, from a nested model or a parent reference |
| Aggregation | sum, average, min, max, count, distinct count, custom reducers |
| Virtualization | uniform and variable row heights, scroll-to-reveal, column windowing |
| Layout | leading / scrolling / trailing panes, stretch and last-column fit |
| Selection | single and multi row, single cell, rectangular ranges, ctrl / shift semantics |
| Editing | validated edit sessions, optimistic writes, paste into a range, undo/redo |
| Export | RFC 4180 CSV, grouped CSV, tab-separated clipboard text |
| Saved views | the whole arrangement - query, columns, widths, pins - as JSON |

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
an earlier query can never overwrite a newer one. A superseded fetch is also
handed a cancelled `query.signal`, so the request can be aborted rather than
merely ignored when it lands:

```dart
final source = AsyncDataSource<Employee>(
  (query) async {
    final response = await api.get(
      '/employees',
      query: query.toJson(),
      // Any client with an abort flag: the signal fires when the grid has
      // moved on.
      abort: query.signal,
    );
    return GridResult(
      rows: response.rows.map(Employee.fromJson).toList(),
      totalCount: response.total,
      // Without these, a data bar over a server-paged column has no range to
      // draw against.
      stats: response.stats,
    );
  },
  // A source is editable when it has somewhere to put a write.
  onCommit: (original, updated) => api.put('/employees/${updated.id}', updated),
);

final controller = GridController<Employee>(
  columns: columns,
  dataSource: source,
  // Rows are recognised by identity, so a refresh cannot move the user's
  // selection onto a different row.
  rowKey: (e) => e.id,
  // One request per typed word rather than per keystroke.
  fetchDebounce: const Duration(milliseconds: 250),
);
```

### Grouping a large backend

Grouping normally needs every matching row, because the grid counts the groups
itself. A source that can group server-side answers a lazy query with headers
and counts, and the grid asks for a group's rows when the user opens it:

```dart
class EmployeeSource extends LatticeDataSource<Employee> {
  @override
  bool get supportsLazyGroups => true;

  @override
  Future<GridResult<Employee>> fetch(GridQuery query) async {
    if (!query.lazyGroups) return _page(query);
    final counts = await api.groupCounts(query);
    return GridResult(
      rows: const [],
      totalCount: counts.total,
      groups: [
        for (final group in counts.groups)
          GroupNode<Employee>(
            field: group.field,
            key: group.key,
            label: group.label,
            depth: 0,
            path: group.key,
            keys: [GroupKey(group.field, group.key)],
            declaredCount: group.count,
            loaded: false,
          ),
      ],
    );
  }

  @override
  Future<GroupChildren<Employee>> fetchGroupChildren(
    GridQuery query,
    GroupNode<Employee> node,
  ) async {
    final rows = await api.rowsIn(node.keys, query);
    return GroupChildren(rows: rows);
  }
}
```

### Saving a view

```dart
final json = jsonEncode(controller.saveState().toJson());
// ... later, on another device
controller.restoreState(
  GridViewState.fromJson(jsonDecode(json) as Map<String, Object?>),
);
```

Functions cannot be serialised, so a grouping with a `keyOf` is restored by
supplying it again through `restoreState`'s `resolveGroup`.

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
