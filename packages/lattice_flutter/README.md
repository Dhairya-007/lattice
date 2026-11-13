# lattice_flutter

An open source data grid for Flutter. MIT licensed, no paid tier, no licence
key, no evaluation banner.

```dart
LatticeDataGrid<Employee>(
  controller: controller,
  showFilterRow: true,
  onRowTap: (row) => open(row.data),
)
```

## What it does

- **Virtualized rows.** A fixed row extent lets the viewport jump straight to
  the visible range, so a grid over tens of thousands of rows builds only the
  cells on screen.
- **Frozen columns**, leading and trailing, with the panes locked to one
  vertical offset and the header locked to the body's horizontal one.
- **Column windowing**, so a hundred-column grid builds only the columns
  actually in view.
- **Sorting** from the header: tap to cycle, ctrl or cmd click for a
  multi-column sort with numbered levels.
- **Resizing** by dragging a header edge; double tap the handle to reset.
- **Filtering** via an optional filter row, which picks its operator from the
  column type - substring for text, equality for numbers and dates.
- **Grouping** with an animated chevron, row counts, and per-group aggregates
  shown under the column they belong to.
- **Selection** of rows, cells or rectangular ranges, with full keyboard
  navigation, ctrl/cmd + A to select all and ctrl/cmd + C to copy as TSV.
- **Inline editing** on double tap, Enter or F2, with validation shown in
  place and Escape to roll back. Clicking away commits rather than discarding.
- **Pagination** and a summary footer with grid-wide aggregates.
- **Theming** derived from the ambient Material theme, light and dark, with
  every surface, line and metric overridable.

## How it is put together

All behaviour lives in [`lattice_core`](../lattice_core), a pure Dart engine
with no dependency on Flutter. This package renders that engine's state and
turns gestures and keys back into controller calls.

That split is not ceremony. It means grid behaviour is covered by fast unit
tests instead of widget tests, and it is what makes adapters for other
frameworks possible rather than a rewrite.

```dart
final controller = GridController<Employee>(
  columns: [
    GridColumn(field: 'name', value: (e) => e.name, pin: ColumnPin.start),
    GridColumn(
      field: 'salary',
      type: ColumnType.number,
      value: (e) => e.salary,
      setValue: (e, v) => e.copyWith(salary: v! as num),
      validator: numberRange(min: 0),
    ),
    GridColumn(field: 'department', value: (e) => e.department),
  ],
  dataSource: InMemoryDataSource(employees),
  aggregations: const [Aggregation.sum('salary')],
  columnFit: ColumnFit.stretch,
);
```

Every grid operation is a method on the controller, so a toolbar button and a
header tap go through exactly the same path:

```dart
controller.toggleSort('salary', additive: true);
controller.groupBy('department');
controller.setSearch(query);
controller.setPageSize(100);
final csv = controller.exportCsv();
```

## Keyboard

| Keys | Action |
| --- | --- |
| Arrows | move the active cell |
| Shift + arrows | extend the range |
| Tab / Shift + Tab | next / previous cell |
| Page Up / Page Down | move by a viewport |
| Home / End | first / last row |
| Enter or F2 | start editing |
| Enter while editing | commit |
| Escape | cancel the edit |
| Space | toggle the row's selection |
| Ctrl/Cmd + A | select every row |
| Ctrl/Cmd + C | copy the selection as TSV |

## Example

```
cd example && flutter run
```

The demo puts 20,000 generated log lines behind the grid, with grouping,
pagination, a filter row, custom cell widgets, a severity-aware comparator and
editable cells.

## Licence

MIT.
