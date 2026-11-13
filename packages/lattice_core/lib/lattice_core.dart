/// A framework-agnostic data grid engine.
///
/// Everything a data grid does other than paint - sorting, filtering,
/// grouping, aggregation, virtualization, selection, editing and export -
/// lives here in pure Dart, with no dependency on Flutter or any other UI
/// toolkit. [GridController] is the entry point: give it columns and a
/// [LatticeDataSource], then render [GridController.visibleRows].
library;

export 'src/aggregate.dart';
export 'src/column.dart';
export 'src/compare.dart';
export 'src/controller.dart';
export 'src/data_source.dart';
export 'src/editing.dart';
export 'src/export.dart';
export 'src/filter.dart';
export 'src/group.dart';
export 'src/layout.dart';
export 'src/notifier.dart';
export 'src/query.dart';
export 'src/rows.dart';
export 'src/selection.dart';
export 'src/sort.dart';
export 'src/virtualization.dart';
