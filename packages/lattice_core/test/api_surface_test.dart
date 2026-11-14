// The everyday library is a promise; this says what is in it.
//
// Anything exported is something a user can hold, and taking it back later
// is a breaking change. The pipeline stages and the few implementation types
// the engine hands around live in advanced.dart instead, so that the surface
// an application sees is the surface it needs.
import 'package:lattice_core/advanced.dart' as advanced;
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('the everyday library carries what an application holds', () {
    // A compile-time assertion as much as a test: if any of these stopped
    // being exported, this file would not analyze.
    expect(GridController<Product>, isNotNull);
    expect(GridColumn<Product>, isNotNull);
    expect(GridQuery, isNotNull);
    expect(GridResult<Product>, isNotNull);
    expect(LatticeDataSource<Product>, isNotNull);
    expect(SourceCapabilities, isNotNull);
    expect(GridViewState, isNotNull);
    expect(TreeSpec<Product>, isNotNull);
    expect(EditHistory<Product>, isNotNull);
    expect(PasteResult, isNotNull);
    expect(FetchSignal, isNotNull);
    expect(GridChange.rows, isNotNull);
    // An adapter needs these two to draw, so they stay in the everyday
    // surface: row geometry and the stacked header bands.
    expect(RowMetrics.uniform(rowCount: 1, rowHeight: 1), isNotNull);
    expect(layoutHeaderRow, isNotNull);
    expect(computeLayout<Product>, isNotNull);
    expect(orderColumnsForDisplay<Product>, isNotNull);
  });

  test('the pipeline stages are reachable from advanced.dart', () {
    expect(advanced.sortRows<Product>, isNotNull);
    expect(advanced.buildComparator<Product>, isNotNull);
    expect(advanced.buildGroups<Product>, isNotNull);
    expect(advanced.flattenGroups<Product>, isNotNull);
    expect(advanced.collectGroupPaths<Product>, isNotNull);
    expect(advanced.flattenTree<Product>, isNotNull);
    expect(advanced.collectTreePaths<Product>, isNotNull);
    expect(advanced.rootsOf<Product>, isNotNull);
    expect(advanced.computeAggregates<Product>, isNotNull);
    expect(advanced.computeColumnStats, isNotNull);
    expect(advanced.describeHeaderProblems<Product>, isNotNull);
  });

  test('advanced.dart is a superset, so one import is enough', () {
    expect(advanced.GridController<Product>, isNotNull);
    expect(advanced.LazyDataRowList<Product>, isNotNull);
    expect(advanced.Float64ListLike, isNotNull);
  });
}
