/// The engine's pipeline, for code that runs it rather than uses it.
///
/// `package:lattice_core/lattice_core.dart` is the surface an application
/// needs: a controller, columns, a data source, and the specs that describe
/// what to show. This library adds the stages the controller drives - the
/// sorter, the grouper, the aggregator, the flatteners - plus the few
/// implementation types they hand back.
///
/// Reach for it when you are writing a [LatticeDataSource] of your own and
/// want to run part of the pipeline locally, or an adapter for another
/// toolkit. Everything here is lower level and shaped by what the engine
/// needs rather than by what reads well at a call site; the everyday library
/// deliberately does not export it, so that a published API is a promise
/// about the things applications actually hold.
library;

export 'lattice_core.dart';
export 'src/aggregate.dart' show computeAggregates;
export 'src/decoration.dart' show computeColumnStats;
export 'src/group.dart' show buildGroups;
export 'src/rows.dart'
    show
        DetailRowList,
        LazyDataRowList,
        collectGroupPaths,
        flattenGroups,
        withDetailRows;
export 'src/sort.dart' show buildComparator, sortRows;
export 'src/stacked_header.dart' show describeHeaderProblems;
export 'src/tree.dart' show collectTreePaths, flattenTree, rootsOf;
export 'src/virtualization.dart' show Float64ListLike, FloatList;
