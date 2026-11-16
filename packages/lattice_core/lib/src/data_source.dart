/// Data sources: the seam between the grid and wherever rows come from.
library;

import 'dart:collection';

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
    _columnTypesCache = null;
    _revision++;
  }

  Map<String, ColumnType>? _columnTypesCache;

  /// Each column's declared type, for compiling a filter against it.
  ///
  /// Built once per set of columns rather than per filter pass: it is what
  /// tells [Filter.compile] that `'50'` typed into this column means the
  /// number 50.
  Map<String, ColumnType> get columnTypes => _columnTypesCache ??= {
        for (final column in _columns.values) column.field: column.type,
      };

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

  /// The distinct values of [field] for a checkbox filter list.
  ///
  /// Returns [DistinctValues.none] when the source cannot answer cheaply,
  /// which an adapter reads as "offer a text filter instead" rather than as
  /// "this column is empty". [limit] caps the list: a value picker over a
  /// high-cardinality column is unusable anyway, and a source should not
  /// materialise a million strings to be told so - [DistinctValues.truncated]
  /// says whether it had to stop.
  ///
  /// The values are computed over the rows that match every *other* filter,
  /// not over the rows that match this column's own: a list narrowed by the
  /// column's own filter offers only the values already picked, so a user who
  /// chooses "Input" can never add "Display" to the selection.
  DistinctValues distinctValuesFor(String field, {int limit = 500}) =>
      DistinctValues.none;

  /// Every row this source holds, or null when it cannot say.
  ///
  /// A source that holds its rows locally returns them; one that pages a
  /// backend returns null, because it has no list to return. The grid uses
  /// this to find a row it has to write to but is not showing - an undo over
  /// a row on another page, inside a closed group, or filtered out of view -
  /// which it previously looked for among the visible rows alone and
  /// therefore silently skipped.
  List<T>? get localRows => null;

  /// Tells the grid to re-run its current query, e.g. after a write.
  void invalidate() => notifyListeners();
}

/// The distinct values of one column, and whether there are more.
///
/// A plain list could not say: the list was read one value over the limit so
/// that a caller could tell, and then cut back to the limit before it was
/// returned, which threw away the only evidence. A checkbox filter list that
/// cannot tell a complete list from a truncated one shows the user a set of
/// values and lets them believe it is all of them.
class DistinctValues {
  const DistinctValues(this.values, {this.truncated = false});

  /// Nothing to offer, from a source that cannot answer.
  static const DistinctValues none = DistinctValues([]);

  /// The values, ascending. A truncated list holds the smallest ones.
  final List<Object?> values;

  /// Whether the column holds more values than the limit allowed.
  final bool truncated;

  bool get isEmpty => values.isEmpty;
  bool get isNotEmpty => values.isNotEmpty;
  int get length => values.length;

  @override
  String toString() =>
      'DistinctValues(${values.length}${truncated ? '+' : ''})';
}

/// Serves rows from a list already in memory.
///
/// Runs the whole pipeline locally - filter, search, sort, group, aggregate,
/// page - and is the source used by the vast majority of grids.
///
/// Up to around 20k rows every operation stays inside a 16.7 ms frame on a
/// desktop machine. Between there and 100k, sorting and a whole-table search
/// cross it: a three-column sort of 50k rows takes about 60 ms, which reads
/// as a stall rather than a dropped frame. Past 100k, prefer a source that
/// pushes the work into a database. `benchmark/grid_benchmark.dart` measures
/// all of it, and `benchmark/budgets.dart` records what each operation is
/// allowed to cost.
class InMemoryDataSource<T> extends LatticeDataSource<T> {
  InMemoryDataSource(List<T> rows) : _rows = List<T>.of(rows);

  List<T> _rows;

  /// The current, unprocessed rows.
  List<T> get rows => List<T>.unmodifiable(_rows);

  @override
  List<T>? get localRows => _rows;

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
    final index = indexOfRow(original);
    if (index < 0) {
      throw StateError('The edited row is no longer in the source.');
    }
    // Writes through the list, which notifies and re-runs the query, so an
    // edit that changes the sort key moves its row immediately.
    replaceAt(index, updated);
    return updated;
  }

  /// The position of [row], found by identity before equality.
  ///
  /// `indexOf` uses `==`, so two rows a model calls equal - two identical
  /// records, two freezed or equatable values with the same fields - were
  /// indistinguishable, and editing the second wrote over the first. The
  /// row the caller handed us is the row we hold, so identity is the right
  /// question; equality stays as the fallback for a model that returns a
  /// fresh equal instance.
  int indexOfRow(T row) {
    for (var i = 0; i < _rows.length; i++) {
      if (identical(_rows[i], row)) return i;
    }
    return _rows.indexOf(row);
  }

  /// Replaces every row in [writes], notifying once.
  ///
  /// A paste of 200 cells across 20 rows would otherwise re-run the query 20
  /// times, and each of those re-runs re-sorts.
  @override
  Future<List<T>> commitAll(List<RowUpdate<T>> writes) async {
    if (writes.isEmpty) return const [];
    // One identity index for the whole batch: locating each row with a scan
    // made a paste of n rows O(n x rows).
    final positions = Map<T, int>.identity();
    for (var i = _rows.length - 1; i >= 0; i--) {
      positions[_rows[i]] = i;
    }
    final indices = <int>[];
    final taken = <int>{};
    for (final write in writes) {
      var index = positions[write.original] ?? -1;
      if (index < 0 || taken.contains(index)) {
        // No identity match: take the first equal row no other write in this
        // batch has claimed, so two equal rows edited together still land in
        // two places.
        index = -1;
        for (var i = 0; i < _rows.length; i++) {
          if (!taken.contains(i) && _rows[i] == write.original) {
            index = i;
            break;
          }
        }
      }
      if (index < 0) {
        throw StateError('An edited row is no longer in the source.');
      }
      taken.add(index);
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
    _lastQuery = query;
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
        sourceIndexOf: sourceIndexOf,
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
        sourceIndexOf: sourceIndexOf,
      );
    }

    return GridResult<T>(
      rows: List<T>.of(ordered),
      totalCount: total,
      filteredCount: matched.length,
      aggregates: aggregates,
      sourceIndexOf: sourceIndexOf,
    );
  }

  // -- Source positions -----------------------------------------------------

  int _positionGeneration = -1;
  Map<T, int>? _positions;

  /// Where [row] sits in the unordered, unfiltered list.
  ///
  /// The grid used to report a row's position in the *sorted* result as its
  /// source index, which is a different number as soon as anything is sorted,
  /// and -1 for every grouped or tree row even though the rows were right
  /// here. The lookup is keyed by identity - two equal rows are two rows -
  /// and built on the first call per matched set, so a grid that never asks
  /// pays nothing.
  int sourceIndexOf(T row) {
    var positions = _positions;
    if (positions == null || _positionGeneration != _matchedGeneration) {
      positions = Map<T, int>.identity();
      for (var i = 0; i < _matchedIndices.length; i++) {
        positions[_matchedRows[i]] = _matchedIndices[i];
      }
      _positions = positions;
      _positionGeneration = _matchedGeneration;
    }
    return positions[row] ?? -1;
  }

  // -- Stage 1: rows that match the filter and the search -------------------

  int _matchedRevision = -1;
  String _matchedKey = '';

  /// Bumped whenever the matched set is recomputed.
  ///
  /// The stats and distinct-value caches key on this instead of on
  /// `'$revision\u0000$_matchedKey'`: building that string per call cost real
  /// time on the conditional-formatting path, which asks for a column's stats
  /// once per visible cell.
  int _matchedGeneration = 0;
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
    // Compiled once per pass, not once per row: this is where an `isIn` over
    // a thousand checkbox values stops being O(rows x values), and where a
    // '50' typed into a number column's filter becomes the number 50.
    final compiled = applyFilter ? filter.compile(types: columnTypes) : null;
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
      if (compiled != null && !compiled.test((f) => columns[f]?.value(row))) {
        continue;
      }
      indices.add(i);
      out.add(row);
    }

    _matchedRevision = revision;
    _matchedKey = key;
    _matchedGeneration++;
    _matchedFilterKey = filterKey;
    _matchedNeedle = needle;
    _matchedIndices = indices;
    _matchedRows = out;
    return out;
  }

  // -- Column statistics ----------------------------------------------------

  int _statsGeneration = -1;
  final Map<String, ColumnStats> _stats = {};

  /// Range of [field] across the rows that currently match.
  ///
  /// Computed over the matched set rather than every row, so a data bar is
  /// drawn against what the user can actually see. Cached per revision and
  /// per matched set, because a bar must not cost a column scan per frame.
  @override
  ColumnStats statsFor(String field) {
    if (_statsGeneration != _matchedGeneration) {
      _stats.clear();
      _statsGeneration = _matchedGeneration;
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

  int _distinctGeneration = -1;
  int _distinctLimit = -1;
  String _distinctScope = '';
  final Map<String, DistinctValues> _distinct = {};

  /// The last query this source resolved, so a distinct-value list knows
  /// which filters to leave out.
  GridQuery? _lastQuery;

  /// The distinct values of [field] among the rows that match every filter
  /// except this column's own.
  ///
  /// Cached exactly as [statsFor] is, and for the same reason: a checkbox
  /// filter list is rebuilt every time the menu opens, and scanning a column
  /// per frame is not affordable.
  ///
  /// Three things used to be wrong with it. The list was cut back to [limit]
  /// after being read one over, so a truncated list was indistinguishable
  /// from a complete one. The values kept were the first ones *seen* rather
  /// than the smallest, so a truncated list was an arbitrary sample shown in
  /// sorted order. And the rows scanned were the ones matching every filter
  /// including this column's, so picking a value left that value as the only
  /// one on offer.
  @override
  DistinctValues distinctValuesFor(String field, {int limit = 500}) {
    final scope = _distinctScopeKey;
    if (_distinctGeneration != _matchedGeneration ||
        _distinctLimit != limit ||
        _distinctScope != scope) {
      _distinct.clear();
      _distinctGeneration = _matchedGeneration;
      _distinctLimit = limit;
      _distinctScope = scope;
    }
    final cached = _distinct[field];
    if (cached != null) return cached;

    final column = columns[field];
    if (column == null) return DistinctValues.none;

    // A sorted set bounded at [limit]: the largest value is dropped as soon
    // as one too many arrives, so what survives is the smallest [limit]
    // values and the list is a prefix of the real one. Stopping the scan
    // early instead bounded the time and gave back an arbitrary sample shown
    // in sorted order, which reads exactly like a complete list. The limit
    // bounds what is held, not what is read.
    final seen = SplayTreeSet<Object?>(compareValues);
    var truncated = false;
    for (final row in _rowsForDistinct(field)) {
      final value = column.value(row);
      if (seen.contains(value)) continue;
      seen.add(value);
      if (seen.length > limit) {
        seen.remove(seen.last);
        truncated = true;
      }
    }
    final out = DistinctValues(
      List<Object?>.unmodifiable(seen),
      truncated: truncated,
    );
    _distinct[field] = out;
    return out;
  }

  /// The rows a distinct-value list for [field] is computed over: those that
  /// match the rest of the query, with any condition on [field] itself left
  /// out.
  Iterable<T> _rowsForDistinct(String field) {
    final query = _lastQuery;
    if (query == null) return _rows;
    final filter = pruneFilter(query.filter, (f) => f != field);
    final needle = query.needle;
    if (filter == null && needle.isEmpty) return _rows;
    final compiled = filter?.compile(types: columnTypes);
    final index =
        needle.isEmpty ? null : _searchIndexFor(_searchFieldsFor(query));
    return [
      for (var i = 0; i < _rows.length; i++)
        if (index == null || index[i].contains(needle))
          if (compiled == null ||
              compiled.test((f) => columns[f]?.value(_rows[i])))
            _rows[i],
    ];
  }

  /// Identity of the scope a distinct-value list is computed over.
  String get _distinctScopeKey {
    final query = _lastQuery;
    if (query == null) return '';
    return '${query.filter?.fingerprint ?? ''}\u0000${query.needle}';
  }

  // -- The search index -----------------------------------------------------

  int _indexRevision = -1;
  String _indexKey = '';
  List<String> _searchIndex = const [];

  /// One folded, searchable string per row, covering [fields].
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
      index[i] = foldText(buffer.toString());
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
