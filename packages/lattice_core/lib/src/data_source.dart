/// Data sources: the seam between the grid and wherever rows come from.
library;

import 'aggregate.dart';
import 'column.dart';
import 'filter.dart';
import 'group.dart';
import 'notifier.dart';
import 'query.dart';
import 'sort.dart';

/// Supplies rows for a [GridQuery].
///
/// Implement this to put a grid in front of anything: a list in memory, a
/// SQLite table, a REST endpoint, a stream. The grid only ever asks for the
/// page it is about to show, so a remote source never has to materialise the
/// whole table.
abstract class LatticeDataSource<T> with GridChangeNotifier {
  /// Columns, so the source can read and compare values.
  ///
  /// Set by the controller before the first fetch.
  Map<String, GridColumn<T>> columns = const {};

  /// Whether rows are resolved locally. Remote sources return false, which
  /// tells the grid to re-query on every sort, filter or page change.
  bool get isLocal => false;

  /// Resolves [query].
  Future<GridResult<T>> fetch(GridQuery query);

  /// Tells the grid to re-run its current query, e.g. after a write.
  void invalidate() => notifyListeners();
}

/// Serves rows from a list already in memory.
///
/// Runs the whole pipeline locally - filter, search, sort, group, aggregate,
/// page - and is the source used by the vast majority of grids. For ~100k
/// rows this stays comfortably inside a frame budget; past that, prefer a
/// source that pushes the work into a database.
class InMemoryDataSource<T> extends LatticeDataSource<T> {
  InMemoryDataSource(List<T> rows) : _rows = List<T>.of(rows);

  List<T> _rows;

  /// The current, unprocessed rows.
  List<T> get rows => List<T>.unmodifiable(_rows);

  int get length => _rows.length;

  @override
  bool get isLocal => true;

  /// Replaces every row and refreshes the grid.
  void setRows(Iterable<T> rows) {
    _rows = List<T>.of(rows);
    notifyListeners();
  }

  void add(T row) {
    _rows.add(row);
    notifyListeners();
  }

  void addAll(Iterable<T> rows) {
    _rows.addAll(rows);
    notifyListeners();
  }

  void insert(int index, T row) {
    _rows.insert(index, row);
    notifyListeners();
  }

  bool remove(T row) {
    final removed = _rows.remove(row);
    if (removed) notifyListeners();
    return removed;
  }

  void removeAt(int index) {
    _rows.removeAt(index);
    notifyListeners();
  }

  void removeWhere(bool Function(T row) test) {
    final before = _rows.length;
    _rows.removeWhere(test);
    if (_rows.length != before) notifyListeners();
  }

  /// Replaces the row at [index], as an edit commit does.
  void replaceAt(int index, T row) {
    _rows[index] = row;
    notifyListeners();
  }

  void clear() {
    if (_rows.isEmpty) return;
    _rows = <T>[];
    notifyListeners();
  }

  @override
  Future<GridResult<T>> fetch(GridQuery query) async => fetchSync(query);

  /// Synchronous [fetch], for adapters that can render in the same frame.
  GridResult<T> fetchSync(GridQuery query) {
    final total = _rows.length;
    var working = _rows;

    if (query.filter != null) {
      working = [
        for (final row in working)
          if (query.filter!.matches(_asMap(row, query.filter!.fields))) row,
      ];
    }

    if (query.hasSearch) {
      final fields = query.searchFields.isNotEmpty
          ? query.searchFields
          : [
              for (final c in columns.values)
                if (c.visible) c.field,
            ];
      final needle = query.search.trim().toLowerCase();
      working = [
        for (final row in working)
          if (_matchesSearch(row, fields, needle)) row,
      ];
    }

    final matched = working.length;

    if (query.sorts.isNotEmpty) {
      working = sortRows<T>(working, query.sorts, columns);
    }

    final aggregates = computeAggregates<T>(
      working,
      query.aggregations,
      (row, field) => columns[field]?.value(row),
    );

    if (query.isGrouped) {
      // Grouping needs the full matched set: a group header must count every
      // row in its group, not just the ones on the current page.
      return GridResult<T>(
        rows: const [],
        groups: buildGroups<T>(
          working,
          query.groups,
          columns,
          aggregations: query.aggregations,
        ),
        totalCount: total,
        filteredCount: matched,
        aggregates: aggregates,
      );
    }

    if (query.offset > 0 || query.limit != null) {
      final start = query.offset.clamp(0, working.length);
      final end = query.limit == null
          ? working.length
          : (start + query.limit!).clamp(start, working.length);
      working = working.sublist(start, end);
    }

    return GridResult<T>(
      rows: working is List<T> ? List<T>.of(working) : working.toList(),
      totalCount: total,
      filteredCount: matched,
      aggregates: aggregates,
    );
  }

  bool _matchesSearch(T row, List<String> fields, String needle) {
    for (final field in fields) {
      final column = columns[field];
      if (column == null) continue;
      final text = column.formattedValue(row).toLowerCase();
      if (text.contains(needle)) return true;
    }
    return false;
  }

  /// Projects just the fields a filter touches, so filtering a wide table does
  /// not build a full map per row.
  Map<String, Object?> _asMap(T row, Set<String> fields) {
    return {
      for (final field in fields) field: columns[field]?.value(row),
    };
  }
}

/// Wraps an async callback as a data source.
///
/// The quickest way to point a grid at an HTTP endpoint: translate the
/// [GridQuery] into request parameters and return the page the server sent.
class AsyncDataSource<T> extends LatticeDataSource<T> {
  AsyncDataSource(this._fetch);

  final Future<GridResult<T>> Function(GridQuery query) _fetch;

  @override
  Future<GridResult<T>> fetch(GridQuery query) => _fetch(query);
}

/// Convenience filter for a quick-search box, matching [needle] against any of
/// [fields] with `contains`.
Filter searchFilter(String needle, List<String> fields) {
  return FilterGroup.or([
    for (final field in fields)
      FilterCondition(
        field: field,
        operator: FilterOperator.contains,
        value: needle,
      ),
  ]);
}
