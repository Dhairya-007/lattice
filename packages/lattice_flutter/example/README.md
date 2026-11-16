# Example

A runnable Flutter app with the grid in it: frozen columns, a sortable header,
a filter row, grouping with subtotals, range selection and inline editing.

```bash
cd example
flutter run
```

The app is [`lib/main.dart`](lib/main.dart). The shape of it:

```dart
import 'package:lattice_flutter/lattice_flutter.dart';

LatticeDataGrid<Employee>(
  controller: GridController<Employee>(
    columns: [
      GridColumn<Employee>(
        field: 'name',
        value: (e) => e.name,
        pin: ColumnPin.start,
      ),
      GridColumn<Employee>(
        field: 'salary',
        type: ColumnType.number,
        value: (e) => e.salary,
        setValue: (e, v) => e..salary = v! as num,
      ),
    ],
    dataSource: InMemoryDataSource<Employee>(employees),
    rowKey: (e) => e.name,
  ),
)
```

Everything the grid *does* — the sorting, the filtering, the selection rules,
the editing — lives in [`lattice_core`](https://pub.dev/packages/lattice_core)
and is unit tested without pumping a frame. This package paints it and turns
gestures into controller calls.
