/// Data sources: the seam between the grid and wherever rows come from.
library;

import 'aggregate.dart';
import 'column.dart';
import 'decoration.dart';
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
  Map<String, GridColumn<T>> _columns = const {};
  int _revision = 0;

  /// Columns, so the source can read and compare values.
  ///
  /// Set by the controller before the first fetch. Assigning bumps
  /// [revision], because a new formatter or accessor invalidates anything
  /// derived from the old ones.
  Map<String, GridColumn<T>> get columns => _columns;

  set columns(Map<String, GridColumn<T>> value) {
    _columns = value;
    _revision++;
  }

  /// Increments whenever the rows or columns change.
  ///
  /// Anything derived from the data - a filtered list, a search index - is
  /// only valid for one revision.
  int get revision => _revision;

  /// Marks derived state stale. Call from any mutator.
  void bumpRevision() => _revision++;

  /// Whether rows are resolved locally. Remote sources return false, which
  /// tells the grid to re-query on every sort, filter or page change.
  bool get isLocal => false;

  /// Resolves [query].
  Future<GridResult<T>> fetch(GridQuery query);

  /// Range of the values currently shown in [field], for conditional
  /// formatting. Sources that cannot answer cheaply return
  /// [ColumnStats.empty], which leaves rules inert rather than wrong.
  ColumnStats statsFor(String field) => ColumnStats.empty;

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
    bumpRevision();
    notifyListeners();
  }

  void add(T row) {
    _rows.add(row);
    bumpRevision();
    notifyListeners();
  }

  void addAll(Iterable<T> rows) {
    _rows.addAll(rows);
    bumpRevision();
    notifyListeners();
  }

  void insert(int index, T row) {
    _rows.insert(index, row);
    bumpRevision();
    notifyListeners();
  }

  bool remove(T row) {
    final removed = _rows.remove(row);
    if (removed) {
      bumpRevision();
      notifyListeners();
    }
    return removed;
  }

  void removeAt(int index) {
    _rows.removeAt(index);
    bumpRevision();
    notifyListeners();
  }

  void removeWhere(bool Function(T row) test) {
    final before = _rows.length;
    _rows.removeWhere(test);
    if (_rows.length != before) {
      bumpRevision();
      notifyListeners();
    }
  }

  /// Replaces the row at [index], as an edit commit does.
  void replaceAt(int index, T row) {
    _rows[index] = row;
    bumpRevision();
    notifyListeners();
  }

  void clear() {
    if (_rows.isEmpty) return;
    _rows = <T>[];
    bumpRevision();
    notifyListeners();
  }

  @override
  Future<GridResult<T>> fetch(GridQuery query) async => fetchSync(query);

  /// Synchronous [fetch], for adapters that can render in the same frame.
  ///
  /// The pipeline is memoised in three stages - matched, then ordered, then
  /// grouped - each keyed by the part of the query it depends on and by
  /// [revision]. That is what makes the common interactions cheap: turning a
  /// page only re-slices, and reversing a sort does not re-filter.
  GridResult<T> fetchSync(GridQuery query) {
    final total = _rows.length;
    final matched = _matchedFor(query);
    final ordered = _orderedFor(query, matched);
    final aggregates = _aggregatesFor(query, ordered);

    if (query.isGrouped) {
      // Grouping needs the full matched set: a group header must count every
      // row in its group, not just the ones on the current page.
      return GridResult<T>(
        rows: const [],
        groups: _groupsFor(query, ordered),
        totalCount: total,
        filteredCount: matched.length,
        aggregates: aggregates,
      );
    }

    if (query.offset > 0 || query.limit != null) {
      final start = query.offset.clamp(0, ordered.length);
      final end = query.limit == null
          ? ordered.length
          : (start + query.limit!).clamp(start, ordered.length);
      return GridResult<T>(
        rows: ordered.sublist(start, end),
        totalCount: total,
        filteredCount: matched.length,
        aggregates: aggregates,
      );
    }

    return GridResult<T>(
      rows: List<T>.of(ordered),
      totalCount: total,
      filteredCount: matched.length,
      aggregates: aggregates,
    );
  }

  // -- Stage 1: rows that match the filter and the search -------------------

  int _matchedRevision = -1;
  String _matchedKey = '';
  String _matchedFilterKey = '';
  String _matchedNeedle = '';
  List<int> _matchedIndices = const [];
  List<T> _matchedRows = const [];

  List<String> _searchFieldsFor(GridQuery query) {
    if (query.searchFields.isNotEmpty) return query.searchFields;
    return [
      for (final c in columns.values)
        if (c.visible) c.field,
    ];
  }

  List<T> _matchedFor(GridQuery query) {
    final fields = _searchFieldsFor(query);
    final needle = query.search.trim().toLowerCase();
    final filterKey =
        '${query.filter?.fingerprint ?? ''}\u0000${fields.join(',')}';
    final key = '$filterKey\u0000$needle';
    if (_matchedRevision == revision && _matchedKey == key) {
      return _matchedRows;
    }

    // Typing another character can only shrink the result, so the new needle
    // is searched within the previous match rather than over every row. The
    // first keystroke narrows the filter-only result for the same reason.
    // This is why indices are cached alongside the rows.
    final canNarrow = _matchedRevision == revision &&
        _matchedFilterKey == filterKey &&
        needle.isNotEmpty &&
        needle.startsWith(_matchedNeedle);

    final filter = query.filter;
    final index = needle.isEmpty ? null : _searchIndexFor(fields);
    // Narrowing has already applied the filter to these rows.
    final applyFilter = filter != null && !canNarrow;
    final candidates = canNarrow
        ? _matchedIndices
        : List<int>.generate(_rows.length, (i) => i, growable: false);

    final indices = <int>[];
    final out = <T>[];
    for (final i in candidates) {
      // Search first: a contains over the prebuilt index is cheaper than
      // walking a filter tree.
      if (index != null && !index[i].contains(needle)) continue;
      final row = _rows[i];
      if (applyFilter && !filter.matchesRow((f) => columns[f]?.value(row))) {
        continue;
      }
      indices.add(i);
      out.add(row);
    }

    _matchedRevision = revision;
    _matchedKey = key;
    _matchedFilterKey = filterKey;
    _matchedNeedle = needle;
    _matchedIndices = indices;
    _matchedRows = out;
    return out;
  }

  // -- Column statistics ----------------------------------------------------

  String _statsKey = '';
  final Map<String, ColumnStats> _stats = {};

  /// Range of [field] across the rows that currently match.
  ///
  /// Computed over the matched set rather than every row, so a data bar is
  /// drawn against what the user can actually see. Cached per revision and
  /// per matched set, because a bar must not cost a column scan per frame.
  @override
  ColumnStats statsFor(String field) {
    final key = '$revision\u0000$_matchedKey';
    if (_statsKey != key) {
      _stats.clear();
      _statsKey = key;
    }
    final cached = _stats[field];
    if (cached != null) return cached;
    final column = columns[field];
    final rows =
        _matchedRows.isEmpty && _matchedKey.isEmpty ? _rows : _matchedRows;
    final stats = column == null
        ? ColumnStats.empty
        : computeColumnStats(rows.map(column.value));
    _stats[field] = stats;
    return stats;
  }

  // -- The search index -----------------------------------------------------

  int _indexRevision = -1;
  String _indexKey = '';
  List<String> _searchIndex = const [];

  /// One lowercased, searchable string per row, covering [fields].
  ///
  /// Quick search is the most repeated operation a grid does - once per
  /// keystroke - and formatting every cell of every row each time dominated
  /// it. Formatting happens once per revision instead.
  ///
  /// Columns are joined with a character a user cannot type, so a search can
  /// never match text that spans two columns.
  List<String> _searchIndexFor(List<String> fields) {
    final key = fields.join(',');
    if (_indexRevision == revision && _indexKey == key) return _searchIndex;

    final resolved = [
      for (final field in fields)
        if (columns[field] != null) columns[field]!,
    ];
    final buffer = StringBuffer();
    final index = List<String>.filled(_rows.length, '');
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      buffer.clear();
      for (var c = 0; c < resolved.length; c++) {
        if (c > 0) buffer.write('\u0001');
        buffer.write(resolved[c].formattedValue(row));
      }
      index[i] = buffer.toString().toLowerCase();
    }

    _indexRevision = revision;
    _indexKey = key;
    _searchIndex = index;
    return index;
  }

  // -- Stage 2: ordering ----------------------------------------------------

  int _orderedRevision = -1;
  String _orderedKey = '';
  List<T> _orderedRows = const [];

  List<T> _orderedFor(GridQuery query, List<T> matched) {
    if (query.sorts.isEmpty) return matched;
    final key = '$_matchedKey\u0000'
        '${query.sorts.map((s) => '${s.field}:${s.direction.name}:${s.nulls.name}').join(',')}';
    if (_orderedRevision == revision && _orderedKey == key) {
      return _orderedRows;
    }
    final sorted = sortRows<T>(matched, query.sorts, columns);
    _orderedRevision = revision;
    _orderedKey = key;
    _orderedRows = sorted;
    return sorted;
  }

  // -- Stage 3: aggregates and groups ---------------------------------------

  int _aggregateRevision = -1;
  String _aggregateKey = '';
  AggregateResult _aggregateResult = const AggregateResult.empty();

  AggregateResult _aggregatesFor(GridQuery query, List<T> ordered) {
    if (query.aggregations.isEmpty) return const AggregateResult.empty();
    final key = '$_orderedKey\u0000$_matchedKey\u0000'
        '${query.aggregations.map((a) => a.id).join(',')}';
    if (_aggregateRevision == revision && _aggregateKey == key) {
      return _aggregateResult;
    }
    final result = computeAggregates<T>(
      ordered,
      query.aggregations,
      (row, field) => columns[field]?.value(row),
    );
    _aggregateRevision = revision;
    _aggregateKey = key;
    _aggregateResult = result;
    return result;
  }

  int _groupRevision = -1;
  String _groupKey = '';
  List<GroupNode<T>> _groupNodes = const [];

  List<GroupNode<T>> _groupsFor(GridQuery query, List<T> ordered) {
    final key = '$_orderedKey\u0000$_matchedKey\u0000'
        '${query.groups.map((g) => '${g.field}:${g.direction.name}').join(',')}'
        '\u0000${query.aggregations.map((a) => a.id).join(',')}';
    if (_groupRevision == revision && _groupKey == key) return _groupNodes;
    final nodes = buildGroups<T>(
      ordered,
      query.groups,
      columns,
      aggregations: query.aggregations,
    );
    _groupRevision = revision;
    _groupKey = key;
    _groupNodes = nodes;
    return nodes;
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
