# Example

A data grid without a UI: columns, a data source, a sort, a filter, grouping
with an aggregate, and the rows the grid would render. The whole thing runs on
the command line, which is the point of a pure-Dart engine.

```bash
dart example/lattice_core_example.dart
```

The full program is [`lattice_core_example.dart`](lattice_core_example.dart).
The shape of it:

```dart
import 'package:lattice_core/lattice_core.dart';

final grid = GridController<Employee>(
  columns: [
    GridColumn<Employee>(
      field: 'name',
      value: (e) => e.name,
      pin: ColumnPin.start,
    ),
    GridColumn<Employee>(field: 'department', value: (e) => e.department),
    GridColumn<Employee>(
      field: 'salary',
      type: ColumnType.number,
      value: (e) => e.salary,
      setValue: (e, v) => e..salary = v! as num,
      validator: numberRange(min: 0),
    ),
  ],
  dataSource: InMemoryDataSource<Employee>(employees),
  rowKey: (e) => e.name,
  // A subtotal per group, and a total in the footer.
  aggregations: const [Aggregation('salary', type: AggregateType.sum)],
);

// Sort, search and filter the way a header click and a filter row would.
grid.toggleSort('salary');
grid.setSearch('eng');
grid.setColumnFilter(
  'salary',
  const FilterCondition(
    field: 'salary',
    operator: FilterOperator.greaterThan,
    value: 100000,
  ),
);

// Group by a column, as dragging it to a group bar would.
grid.groupBy('department');

// Render: group headers and data rows, in one flat list.
for (final row in grid.visibleRows) {
  switch (row) {
    case GroupGridRow<Employee>(:final label, :final rowCount):
      print('$label ($rowCount)');
    case DataGridRow<Employee>(:final data):
      print('  ${data.name}');
    case DetailGridRow<Employee>():
      break;
  }
}

// Edit a cell, with validation and an undo step.
grid.beginEdit(const CellAddress(0, 'salary'));
grid.updateEdit(150000);
grid.commitEdit();
grid.undo();

// Save the arrangement, and put it back later.
final view = grid.saveState().toJson();
grid.restoreState(GridViewState.fromJson(view));

// Export what is on screen.
print(grid.exportCsv());
```

To draw it, add [`lattice_flutter`](https://pub.dev/packages/lattice_flutter),
or write an adapter for any other toolkit: an adapter reads
`GridController.visibleRows` and `layoutFor`, and turns gestures into
controller calls.
