/// A virtualized, open source data grid for Flutter.
///
/// The widgets here render the state of a [GridController] from
/// `lattice_core` and turn gestures and keys back into controller calls. All
/// grid behaviour - sorting, filtering, grouping, selection, editing - lives
/// in that engine, which is plain Dart and unit tested on its own.
///
/// ```dart
/// final controller = GridController<Employee>(
///   columns: [
///     GridColumn(field: 'name', value: (e) => e.name, pin: ColumnPin.start),
///     GridColumn(field: 'salary', type: ColumnType.number, value: (e) => e.salary),
///   ],
///   dataSource: InMemoryDataSource(employees),
/// );
///
/// LatticeDataGrid<Employee>(controller: controller, showFilterRow: true);
/// ```
library;

export 'package:lattice_core/lattice_core.dart';

export 'src/data_grid.dart';
export 'src/grid_cell.dart' show GridCellBuilder, LatticeCell;
export 'src/grid_header.dart' show LatticeFilterCell, LatticeHeaderCell;
export 'src/group_row.dart' show LatticeGroupRowCells;
export 'src/pager.dart' show LatticeGridFooter;
export 'src/synced_scroll.dart' show SyncedScrollGroup;
export 'src/theme.dart' show LatticeGridTheme;
