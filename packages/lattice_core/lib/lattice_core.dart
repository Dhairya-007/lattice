/// A framework-agnostic data grid engine.
///
/// Everything a data grid does other than paint - sorting, filtering,
/// grouping, aggregation, virtualization, selection, editing and export -
/// lives here in pure Dart, with no dependency on Flutter or any other UI
/// toolkit. [GridController] is the entry point: give it columns and a
/// [LatticeDataSource], then render [GridController.visibleRows].
library;

export 'src/aggregate.dart' hide computeAggregates;
export 'src/column.dart';
export 'src/compare.dart';
export 'src/controller.dart';
export 'src/data_source.dart';
export 'src/decoration.dart' hide computeColumnStats;
export 'src/editing.dart';
export 'src/export.dart';
export 'src/fetch.dart';
export 'src/filter.dart';
export 'src/group.dart' hide buildGroups;
export 'src/history.dart';
export 'src/layout.dart';
export 'src/notifier.dart';
export 'src/paste.dart';
export 'src/query.dart';
export 'src/rows.dart' hide LazyDataRowList, collectGroupPaths, flattenGroups;
export 'src/selection.dart';
export 'src/sort.dart' hide buildComparator, sortRows;
export 'src/stacked_header.dart' hide describeHeaderProblems;
export 'src/tree.dart' hide collectTreePaths, flattenTree, rootsOf;
export 'src/view_state.dart';
export 'src/schema.dart';
export 'src/virtualization.dart' hide Float64ListLike, FloatList;
