/// Data sources: the seam between the grid and wherever rows come from.
library;

import 'aggregate.dart';
import 'column.dart';
import 'compare.dart';
import 'decoration.dart';
import 'filter.dart';
import 'group.dart';
import 'notifier.dart';
import 'query.dart';
import 'sort.dart';

/// What a data source can do, as the source itself declares it.
///
/// The grid used to ask `source is InMemoryDataSource` and treat everything
/// else as a remote source that could do nothing: no editing, no statistics,
/// no distinct values, no cancellation. That made "local or remote" a branch
/// in the engine rather than a property of the source, and every feature
/// worked fully only on a list in memory.
///
/// A source answers for itself instead, and an adapter can read this to stop
/// offering what the source cannot honour - a checkbox filter list for a
/// source with no distinct values, an editor for one that cannot write.
class SourceCapabilities {
  const SourceCapabilities({
    required this.isLocal,
    required this.isSynchronous,
    required this.canWrite,
    required this.providesStats,
    required this.providesDistinctValues,
    required this.supportsLazyGroups,
    required this.supportsCancellation,
    this.supportsLoadMore = true,
  });

  /// Rows are resolved locally, so the grid need not re-query to sort, filter
  /// or page.
  final bool isLocal;

  /// The source can answer inside the frame, through
  /// [LatticeDataSource.fetchSync].
  final bool isSynchronous;

  /// Edits can be written back.
  final bool canWrite;

  /// Column ranges are available, so conditional formatting has something to
  /// draw against.
  final bool providesStats;

  /// A column's distinct values are available, for a checkbox filter list.
  final bool providesDistinctValues;

  /// Group headers and counts can be fetched without their rows.
  final bool supportsLazyGroups;

  /// An in-flight fetch is actually abandoned when the grid cancels it.
  final bool supportsCancellation;

  /// The source can be asked for another slice, for infinite scrolling.
  final bool supportsLoadMore;

  @override
  String toString() => 'SourceCapabilities(${[
        if (isLocal) 'local',
        if (isSynchronous) 'synchronous',
        if (canWrite) 'write',
        if (providesStats) 'stats',
        if (providesDistinctValues) 'distinct',
        if (supportsLazyGroups) 'lazyGroups',
        if (supportsCancellation) 'cancellation',
        if (supportsLoadMore) 'loadMore',
      ].join(', ')})';
}

/// What one group holds, fetched when the user opened it.
class GroupChildren<T> {
  const GroupChildren({
    this.rows = const [],
    this.groups = const [],
    this.aggregates,
  });

  /// Leaf rows, when this was the innermost grouping level.
  final List<T> rows;

  /// Child groups, when another level remains. They may themselves be
  /// unloaded headers, so a deep grouping stays lazy all the way down.
  final List<GroupNode<T>> groups;

  /// Aggregates for the group, if the source computed them now rather than
  /// with the header. Null leaves whatever the header carried.
  final AggregateResult? aggregates;

  bool get isEmpty => rows.isEmpty && groups.isEmpty;
}

/// One row to be written, as it was and as it should become.
class RowUpdate<T> {
  const RowUpdate(this.original, this.updated);

  /// The row as the source currently holds it, so it can be found again.
  final T original;

  /// The row to store in its place.
  final T updated;

  @override
  String toString() => 'RowUpdate($original -> $updated)';
}

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

  /// Whether this source can answer inside the current frame, through
  /// [fetchSync].
  ///
  /// The grid takes that path when it can, which is what spares a local grid
  /// a frame of emptiness on its very first build. It used to ask
  /// `source is InMemoryDataSource`, which meant that any other synchronous
  /// source - a decorator, a test double, a SQLite table read on the same
  /// isolate - was treated as remote however fast it was. A source says what
  /// it can do; the grid does not guess from its type.
  bool get isSynchronous => false;

  /// Resolves [query] now, without awaiting.
  ///
  /// Only called when [isSynchronous] is true, and throws otherwise: a source
  /// that cannot answer immediately has nothing to return here, and returning
  /// an empty result would be a lie the grid would render.
  GridResult<T> fetchSync(GridQuery query) {
    throw UnsupportedError(
      '$runtimeType cannot answer synchronously. Override fetchSync and '
      'isSynchronous, or leave isSynchronous false and implement fetch.',
    );
  }

  /// Resolves [query].
  Future<GridResult<T>> fetch(GridQuery query);

  /// Whether this source can write an edited row back.
  ///
  /// False by default, because a source that only answers [fetch] has nowhere
  /// to put a write. The grid asks before it opens an editor, so a read-only
  /// source does not offer editing it cannot honour.
  bool get canCommit => false;

  /// Writes [updated] back in place of [original].
  ///
  /// Returns the row as the source now holds it, which need not be [updated]:
  /// a server may normalise a value or fill in a timestamp, and the grid shows
  /// what comes back. Throwing rejects the edit, and the grid rolls its
  /// optimistic update back and reports the error.
  ///
  /// Only called when [canCommit] is true.
  Future<T> commit(T original, T updated) {
    throw UnsupportedError(
      '$runtimeType cannot write rows back. Override commit and canCommit to '
      'support editing.',
    );
  }

  /// Writes several rows as one change, returning them in the order given.
  ///
  /// A paste into a range is one user action, so it should be one write: a
  /// source that can send a batch in a single request or a single transaction
  /// overrides this, and the default walks [commit] for a source that cannot.
  /// Either way the grid refreshes once.
  Future<List<T>> commitAll(List<RowUpdate<T>> writes) async {
    final out = <T>[];
    for (final write in writes) {
      out.add(await commit(write.original, write.updated));
    }
    return out;
  }

  /// Whether [statsFor] answers with real ranges rather than
  /// [ColumnStats.empty].
  ///
  /// A conditional formatting rule has nothing to draw against without them,
  /// so an adapter reads this to tell "no rule applies" from "this source
  /// cannot measure the column".
  bool get providesStats => false;

  /// Whether [distinctValuesFor] answers with real values.
  bool get providesDistinctValues => false;

  /// Whether rows exist beyond the last result, for a grid that loads more as
  /// the user scrolls rather than paging.
  ///
  /// A source that cannot know - a REST endpoint that reports no total -
  /// should return true until a fetch comes back short, which is what the
  /// grid's own book-keeping does for [InMemoryDataSource].
  bool get hasMore => false;

  /// Whether this source honours [GridQuery.signal] by abandoning the work.
  ///
  /// False by default, because ignoring the signal is a valid implementation
  /// and claiming otherwise would have an adapter promise the user something
  /// that does not happen.
  bool get supportsCancellation => false;

  /// Whether this source can extend itself a slice at a time.
  ///
  /// Distinct from [hasMore], which is about whether there is anything left:
  /// this is about whether asking is meaningful at all. A source answers a
  /// load-more request through [fetch] with an offset, so the default is to
  /// support it as soon as rows are paged.
  bool get supportsLoadMore => true;

  /// Everything this source can do, in one value.
  SourceCapabilities get capabilities => SourceCapabilities(
        isLocal: isLocal,
        isSynchronous: isSynchronous,
        canWrite: canCommit,
        providesStats: providesStats,
        providesDistinctValues: providesDistinctValues,
        supportsLazyGroups: supportsLazyGroups,
        supportsCancellation: supportsCancellation,
        supportsLoadMore: supportsLoadMore,
      );

  /// Range of the values currently shown in [field], for conditional
  /// formatting. Sources that cannot answer cheaply return
  /// [ColumnStats.empty], which leaves rules inert rather than wrong.
  ColumnStats statsFor(String field) => ColumnStats.empty;

  /// Whether this source can answer a [GridQuery.lazyGroups] query, returning
  /// group headers with counts and the rows of a group only when asked.
  ///
  /// This is what makes grouping usable over a large backend: without it,
  /// grouping has to pull every matching row so the grid can count the
  /// groups itself.
  bool get supportsLazyGroups => false;

  /// Resolves the contents of one group.
  ///
  /// [node] carries the group's [GroupNode.keys], which is what translates
  /// into a filter, and [query] is the query the headers came from, so the
  /// source can apply the same filters, search and ordering within the group.
  ///
  /// Return child groups when another grouping level remains, or rows when
  /// this is the innermost one. Only called when [supportsLazyGroups] is true.
  Future<GroupChildren<T>> fetchGroupChildren(
    GridQuery query,
    GroupNode<T> node,
  ) {
    throw UnsupportedError(
      '$runtimeType cannot resolve a group lazily. Override '
      'fetchGroupChildren and supportsLazyGroups to support it.',
    );
  }

  /// The distinct values of [field] among the rows that currently match, in
  /// ascending order, for a checkbox filter list.
  ///
  /// Returns an empty list when the source cannot answer cheaply, which an
  /// adapter reads as "offer a text filter instead" rather than as "this
  /// column is empty". [limit] caps the list: a value picker over a
  /// high-cardinality column is unusable anyway, and a source should not
  /// materialise a million strings to be told so.
  List<Object?> distinctValuesFor(String field, {int limit = 500}) => const [];

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

  @override
  bool get isSynchronous => true;

  @override
  bool get providesStats => true;

  @override
  bool get providesDistinctValues => true;

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
  bool get canCommit => true;

  @override
  Future<T> commit(T original, T updated) async {
    final index = _rows.indexOf(original);
    if (index < 0) {
      throw StateError('The edited row is no longer in the source.');
    }
    // Writes through the list, which notifies and re-runs the query, so an
    // edit that changes the sort key moves its row immediately.
    replaceAt(index, updated);
    return updated;
  }

  /// Replaces every row in [writes], notifying once.
  ///
  /// A paste of 200 cells across 20 rows would otherwise re-run the query 20
  /// times, and each of those re-runs re-sorts.
  @override
  Future<List<T>> commitAll(List<RowUpdate<T>> writes) async {
    if (writes.isEmpty) return const [];
    final indices = <int>[];
    for (final write in writes) {
      final index = _rows.indexOf(write.original);
      if (index < 0) {
        throw StateError('An edited row is no longer in the source.');
      }
      indices.add(index);
    }
    for (var i = 0; i < writes.length; i++) {
      _rows[indices[i]] = writes[i].updated;
    }
    bumpRevision();
    notifyListeners();
    return [for (final write in writes) write.updated];
  }

  @override
  Future<GridResult<T>> fetch(GridQuery query) async => fetchSync(query);

  /// Synchronous [fetch], for adapters that can render in the same frame.
  ///
  /// The pipeline is memoised in three stages - matched, then ordered, then
  /// grouped - each keyed by the part of the query it depends on and by
  /// [revision]. That is what makes the common interactions cheap: turning a
  /// page only re-slices, and reversing a sort does not re-filter.
  @override
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
    final needle = query.needle;
    // The query states its own identity; see GridQuery's cache identity
    // section. Falling back to the resolved search fields matters because
    // this source substitutes every visible column when the query named
    // none, and that substitution changes what matches.
    final filterKey = fields == query.searchFields
        ? query.filterFingerprint
        : '${query.filter?.fingerprint ?? ''}\u0000${fields.join(',')}';
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

  String _distinctKey = '';
  final Map<String, List<Object?>> _distinct = {};

  /// The distinct values of [field] among the rows that currently match.
  ///
  /// Cached exactly as [statsFor] is, and for the same reason: a checkbox
  /// filter list is rebuilt every time the menu opens, and scanning a column
  /// per frame is not affordable. Truncated at [limit], in which case the
  /// list is the first [limit] values in ascending order.
  @override
  List<Object?> distinctValuesFor(String field, {int limit = 500}) {
    final key = '$revision\u0000$_matchedKey\u0000$limit';
    if (_distinctKey != key) {
      _distinct.clear();
      _distinctKey = key;
    }
    final cached = _distinct[field];
    if (cached != null) return cached;

    final column = columns[field];
    if (column == null) return const [];
    final rows =
        _matchedRows.isEmpty && _matchedKey.isEmpty ? _rows : _matchedRows;
    final seen = <Object?>{};
    for (final row in rows) {
      seen.add(column.value(row));
      // One over the limit, so a caller can tell a truncated list from a
      // complete one by its length.
      if (seen.length > limit) break;
    }
    final values = seen.toList()..sort(compareValues);
    final out = List<Object?>.unmodifiable(
      values.length > limit ? values.sublist(0, limit) : values,
    );
    _distinct[field] = out;
    return out;
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
        '${query.sorts.map((s) => s.fingerprint).join(',')}';
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
        '${query.aggregations.map((a) => a.fingerprint).join(',')}';
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
        // The bucketing functions are part of the key: see
        // [GroupSpec.fingerprint].
        '${query.groups.map((g) => g.fingerprint).join(',')}'
        '\u0000${query.aggregations.map((a) => a.fingerprint).join(',')}';
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
  AsyncDataSource(this._fetch,
      {Future<T> Function(T original, T updated)? onCommit})
      : _commit = onCommit;

  final Future<GridResult<T>> Function(GridQuery query) _fetch;
  final Future<T> Function(T original, T updated)? _commit;

  @override
  Future<GridResult<T>> fetch(GridQuery query) => _fetch(query);

  /// Editable only when an [onCommit] was supplied: there is otherwise no
  /// endpoint to send the write to.
  @override
  bool get canCommit => _commit != null;

  @override
  Future<T> commit(T original, T updated) => _commit!(original, updated);
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
