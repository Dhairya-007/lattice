/// The grid's single source of truth.
library;

import 'dart:async';

import 'aggregate.dart';
import 'column.dart';
import 'data_source.dart';
import 'decoration.dart';
import 'editing.dart';
import 'export.dart';
import 'fetch.dart';
import 'filter.dart';
import 'group.dart';
import 'history.dart';
import 'layout.dart';
import 'paste.dart';
import 'notifier.dart';
import 'query.dart';
import 'rows.dart';
import 'selection.dart';
import 'sort.dart';
import 'stacked_header.dart';
import 'view_state.dart';

/// Owns every piece of grid state and the pipeline that turns it into rows.
///
/// A UI adapter is meant to be a thin shell over this: listen for changes,
/// read [visibleRows] and [layoutFor], and call these methods from gestures.
/// All of the behaviour a data grid is judged on lives here, in plain Dart
/// that can be unit tested without pumping a single frame.
class GridController<T> with GridChangeNotifier {
  GridController({
    required List<GridColumn<T>> columns,
    required LatticeDataSource<T> dataSource,
    List<SortSpec> sorts = const [],
    List<GroupSpec> groups = const [],
    List<Aggregation> aggregations = const [],
    Filter? filter,
    SelectionMode selectionMode = SelectionMode.multiRow,
    List<HeaderRow> stackedHeaders = const [],
    int frozenRowCount = 0,
    int frozenRowCountBottom = 0,
    int? pageSize,
    bool groupsExpandedByDefault = true,
    this.columnFit = ColumnFit.none,
    this.rowKey,
    this.fetchDebounce,
    this.keepRowsOnError = false,
    this.lazyGrouping = false,
  })  : _columns = List<GridColumn<T>>.of(columns),
        _dataSource = dataSource,
        _sorts = List<SortSpec>.of(sorts),
        _groups = List<GroupSpec>.of(groups),
        _aggregations = List<Aggregation>.of(aggregations),
        _filter = filter,
        _stackedHeaders = List<HeaderRow>.of(stackedHeaders),
        _frozenRowCount = frozenRowCount,
        _frozenRowCountBottom = frozenRowCountBottom,
        _pageSize = pageSize,
        selection = SelectionState(mode: selectionMode),
        expansion =
            GroupExpansionState(expandedByDefault: groupsExpandedByDefault) {
    _dataSource.columns = columnsByField;
    _dataSource.addListener(_onSourceChanged);
    refresh();
  }

  List<GridColumn<T>> _columns;
  LatticeDataSource<T> _dataSource;

  List<SortSpec> _sorts;
  List<GroupSpec> _groups;
  final List<Aggregation> _aggregations;
  Filter? _filter;
  final Map<String, FilterCondition> _columnFilters = {};
  String _search = '';
  int? _pageSize;
  int _pageIndex = 0;

  final Map<String, double> _columnWidths = {};
  List<HeaderRow> _stackedHeaders;
  int _frozenRowCount;
  int _frozenRowCountBottom;

  GridResult<T>? _result;
  List<GridRow<T>> _visibleRows = const [];
  bool _loading = false;
  Object? _error;
  int _fetchToken = 0;

  EditSession<T>? _edit;

  /// Row and cell selection.
  final SelectionState selection;

  /// Which group headers are open.
  final GroupExpansionState expansion;

  /// How spare horizontal space is used.
  ColumnFit columnFit;

  /// How long to wait before sending a coalescing refresh, or null for none.
  ///
  /// Applies to the interactions a user drives a character at a time - the
  /// search box and the filter row - and only to a source that is not local.
  /// A few hundred milliseconds turns a typed word into one request.
  Duration? fetchDebounce;

  /// Whether grouping may be resolved one group at a time by the source.
  ///
  /// Grouping otherwise needs every matching row, because the grid counts the
  /// groups itself - so grouping a million-row backend downloads a million
  /// rows. With this on, and a source whose
  /// [LatticeDataSource.supportsLazyGroups] is true, the query asks for
  /// headers and counts only and each group's contents are fetched when it is
  /// opened. Pair it with `groupsExpandedByDefault: false`, or the first
  /// render asks for every group at once and the saving is lost.
  final bool lazyGrouping;

  /// Whether a failed fetch keeps the rows it was replacing.
  ///
  /// Off by default, because stale rows presented as current are a worse lie
  /// than an empty grid. Turn it on for a dashboard that polls, where one
  /// dropped response should not blank the screen; show [error] alongside
  /// them so the user knows what they are looking at is not fresh.
  bool keepRowsOnError;

  /// Recognises a row across rebuilds: a primary key, not a position.
  ///
  /// Everything the user has aimed at a particular row - the selection, the
  /// active cell, an open edit session - is stored as a row index, because an
  /// index is what an adapter renders. An index is a position, so without a
  /// way to recognise the row it pointed at, re-sorting or a background
  /// refresh silently moves the user's selection onto a different row.
  ///
  /// Supply this and those indices are rewritten to wherever the rows went.
  /// Leave it null and the old positional behaviour applies, which is correct
  /// only for a grid whose order never changes under the user.
  ///
  /// The key must be stable for the life of a row and must implement `==` and
  /// `hashCode` - a `String` id, an `int`, or a record of both for a composite
  /// key. Frozen rows stay positional on purpose: see [frozenRowCount].
  final Object Function(T row)? rowKey;

  /// Whether rows can be recognised across rebuilds, i.e. [rowKey] was given.
  bool get hasRowIdentity => rowKey != null;

  /// The identity of [row], or null when no [rowKey] was supplied.
  Object? keyFor(T row) => rowKey?.call(row);

  // -- Read-only view of the state ------------------------------------------

  List<GridColumn<T>> get columns => List.unmodifiable(_columns);

  /// Columns taking part in layout, in the order they appear on screen.
  ///
  /// Pinning moves a column on screen without moving it in the column list,
  /// so this is [orderColumnsForDisplay] over the declared columns rather
  /// than the list itself. Keyboard navigation, range selection and export
  /// all read this, which is what keeps them agreeing with the screen.
  List<GridColumn<T>> get visibleColumns => orderColumnsForDisplay<T>(_columns);

  Map<String, GridColumn<T>> get columnsByField =>
      {for (final c in _columns) c.field: c};

  GridColumn<T>? column(String field) =>
      _columns.where((c) => c.field == field).firstOrNull;

  LatticeDataSource<T> get dataSource => _dataSource;

  List<SortSpec> get sorts => List.unmodifiable(_sorts);
  List<GroupSpec> get groups => List.unmodifiable(_groups);
  List<Aggregation> get aggregations => List.unmodifiable(_aggregations);
  Filter? get filter => _filter;
  Map<String, FilterCondition> get columnFilters =>
      Map.unmodifiable(_columnFilters);
  String get search => _search;

  /// The rows to render, group headers included.
  List<GridRow<T>> get visibleRows => _visibleRows;

  int get rowCount => _visibleRows.length;

  /// Rows that matched the current filters, before paging.
  int get matchedCount => _result?.matchedCount ?? 0;

  /// Rows in the source, before any filtering.
  int get totalCount => _result?.totalCount ?? 0;

  /// Grid-wide aggregates for a summary footer.
  AggregateResult get aggregates =>
      _result?.aggregates ?? const AggregateResult.empty();

  bool get isLoading => _loading;

  /// Error thrown by the last fetch, if it failed.
  Object? get error => _error;

  bool get isGrouped => _groups.isNotEmpty;

  bool get isEmpty => !_loading && _visibleRows.isEmpty;

  /// The in-flight cell edit, if the grid is editing.
  EditSession<T>? get editSession => _edit;

  // -- Paging ---------------------------------------------------------------

  int? get pageSize => _pageSize;
  int get pageIndex => _pageIndex;

  int get pageCount {
    final size = _pageSize;
    if (size == null || size <= 0) return 1;
    final count = (matchedCount / size).ceil();
    return count < 1 ? 1 : count;
  }

  bool get hasNextPage => _pageIndex < pageCount - 1;
  bool get hasPreviousPage => _pageIndex > 0;

  /// Sets the page size, keeping the first row of the current page in view
  /// rather than jumping back to the top.
  void setPageSize(int? size) {
    if (_pageSize == size) return;
    final firstRow = _pageSize == null ? 0 : _pageIndex * _pageSize!;
    _pageSize = size;
    _pageIndex = size == null || size <= 0 ? 0 : firstRow ~/ size;
    refresh();
  }

  void goToPage(int index) {
    final clamped = index.clamp(0, pageCount - 1);
    if (clamped == _pageIndex) return;
    _pageIndex = clamped;
    refresh();
  }

  void nextPage() => goToPage(_pageIndex + 1);
  void previousPage() => goToPage(_pageIndex - 1);

  // -- Query building -------------------------------------------------------

  /// The query the current state describes.
  GridQuery get query {
    final conditions = <Filter>[
      if (_filter != null) _filter!,
      for (final condition in _columnFilters.values)
        if (!condition.isEmpty) condition,
    ];
    final size = _pageSize;
    return GridQuery(
      sorts: _sorts,
      filter: conditions.isEmpty
          ? null
          : (conditions.length == 1
              ? conditions.first
              : FilterGroup.and(conditions)),
      search: _search,
      searchFields: [
        for (final c in visibleColumns)
          if (c.filterable) c.field,
      ],
      groups: _groups,
      aggregations: _aggregations,
      offset: size == null || size <= 0 || isGrouped ? 0 : _pageIndex * size,
      limit: isGrouped ? null : (size != null && size > 0 ? size : null),
      lazyGroups: isLazilyGrouped,
    );
  }

  /// Re-runs the query and rebuilds [visibleRows].
  ///
  /// Concurrent fetches are token-guarded, so a slow response from an earlier
  /// query can never overwrite the result of a newer one, and the superseded
  /// fetch is handed a cancelled [FetchSignal] so a source that honours it
  /// can stop work it no longer has to finish.
  ///
  /// With [coalesce] true and [fetchDebounce] set, the fetch is deferred and
  /// folded into any other coalescing refresh that arrives inside the window.
  /// That is what keeps a filter row from sending one request per keystroke.
  /// A local source is never debounced: it answers inside the frame, so
  /// delaying it would only make typing feel slow.
  Future<void> refresh({bool coalesce = false}) {
    final delay = fetchDebounce;
    if (coalesce &&
        delay != null &&
        delay > Duration.zero &&
        !_dataSource.isLocal) {
      // The in-flight request is answering a query the user has already moved
      // on from.
      _cancelFetch('superseded by a newer query');
      _debounceTimer?.cancel();
      final completer = _debounced ??= Completer<void>();
      _loading = true;
      _error = null;
      notifyListeners();
      _debounceTimer = Timer(delay, () {
        _debounceTimer = null;
        _debounced = null;
        _fetch().whenComplete(() {
          if (!completer.isCompleted) completer.complete();
        });
      });
      return completer.future;
    }
    _debounceTimer?.cancel();
    _debounceTimer = null;
    return _fetch();
  }

  Timer? _debounceTimer;
  Completer<void>? _debounced;
  FetchSignal? _signal;

  /// Whether a debounced refresh is waiting to be sent.
  bool get isFetchPending => _debounceTimer != null;

  void _cancelFetch(String reason) {
    _signal?.cancel(reason);
    _signal = null;
  }

  Future<void> _fetch() async {
    final token = ++_fetchToken;
    final source = _dataSource;
    _cancelFetch('superseded by a newer query');

    // A local source answers synchronously; resolving it inline avoids a
    // frame of empty grid on the very first build.
    if (source is InMemoryDataSource<T>) {
      _loading = false;
      _error = null;
      _apply(source.fetchSync(query));
      return;
    }

    final signal = FetchSignal();
    _signal = signal;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await source.fetch(query.copyWith(signal: signal));
      if (token != _fetchToken || isDisposed) return;
      _loading = false;
      // The groups the source just sent supersede anything cached for the
      // query they replace.
      _loadedGroups.clear();
      _groupErrors.clear();
      _apply(result);
    } on FetchCancelled {
      // A cancelled fetch has no answer and is not a failure: the refresh
      // that replaced it owns the state now.
      return;
    } catch (error) {
      if (token != _fetchToken || isDisposed) return;
      _loading = false;
      _error = error;
      if (!keepRowsOnError) _visibleRows = const [];
      notifyListeners();
    }
  }

  void _apply(GridResult<T> result) {
    // Read the identities the user is pointing at before the rows change
    // under them.
    final tracked = _trackedRowKeys();

    _result = result;
    _visibleRows = result.isGrouped
        ? flattenGroups<T>(
            _mergeLoadedGroups(result.groups),
            expansion,
            loadingPaths: _loadingGroups,
          )
        // Lazy: an ungrouped 50k-row grid must not allocate 50k wrappers on
        // every change. See [LazyDataRowList].
        : LazyDataRowList<T>(
            result.rows,
            offset: query.offset,
            substitute: _pendingWrites.isEmpty ? null : _substituteWrite,
          );

    if (tracked != null) {
      final positions = _rowPositions();
      // A group header has no identity to follow, so it keeps its position.
      // A data row whose identity is gone - filtered out, or deleted
      // elsewhere - is dropped rather than left pointing at its neighbour.
      int? movedFrom(int index) {
        final identity = tracked[index];
        return identity == null ? index : positions[identity];
      }

      selection.remapRows(movedFrom, rowCount: _visibleRows.length);

      final session = _edit;
      if (session != null) {
        final movedTo = movedFrom(session.cell.row);
        if (movedTo == null) {
          // Keeping the editor open over an unrelated row would write the
          // half-typed value into it.
          _edit = null;
        } else {
          session.relocate(movedTo);
        }
      }
    }
    selection.clampTo(_visibleRows.length);
    notifyListeners();
    if (isLazilyGrouped) _requestOpenGroups();
  }

  // -- Lazy grouping --------------------------------------------------------

  /// Contents of the groups fetched so far, keyed by [GroupNode.path].
  final Map<String, GroupChildren<T>> _loadedGroups = {};
  final Set<String> _loadingGroups = <String>{};

  /// Whether grouping is being resolved a group at a time by the source.
  ///
  /// True when [lazyGrouping] is on, the grid is grouped, and the source says
  /// it can answer a [GridQuery.lazyGroups] query. A local source always
  /// groups in full: it already holds every row, so there is nothing to defer.
  bool get isLazilyGrouped =>
      lazyGrouping &&
      isGrouped &&
      !_dataSource.isLocal &&
      _dataSource.supportsLazyGroups;

  /// Whether the grid is waiting for the contents of [path].
  bool isGroupLoading(String path) => _loadingGroups.contains(path);

  /// Grafts the contents fetched for a group onto the header the source sent.
  List<GroupNode<T>> _mergeLoadedGroups(List<GroupNode<T>> nodes) {
    if (_loadedGroups.isEmpty) return nodes;
    return [
      for (final node in nodes)
        () {
          final loaded = _loadedGroups[node.path];
          if (loaded != null) {
            return node.withContents(
              children: _mergeLoadedGroups(loaded.groups),
              rows: loaded.rows,
              aggregates: loaded.aggregates,
            );
          }
          if (node.children.isEmpty) return node;
          return node.withChildren(_mergeLoadedGroups(node.children));
        }(),
    ];
  }

  /// Asks the source for the contents of every open group it has not sent.
  ///
  /// Driven from the rows rather than from the tree, so only groups the user
  /// can actually see are fetched: an open group inside a closed one costs
  /// nothing until its parent is opened.
  void _requestOpenGroups() {
    final pending = <GroupNode<T>>[];
    for (final row in _visibleRows) {
      if (row is! GroupGridRow<T>) continue;
      if (!row.expanded || row.isLoaded) continue;
      final path = row.node.path;
      if (_loadingGroups.contains(path)) continue;
      if (_loadedGroups.containsKey(path)) continue;
      // A group that failed is not retried on every rebuild; see
      // [invalidateGroup].
      if (_groupErrors.containsKey(path)) continue;
      pending.add(row.node);
    }
    if (pending.isEmpty) return;

    for (final node in pending) {
      _loadingGroups.add(node.path);
    }
    // Re-flatten before the requests go out, so an open group says it is
    // loading rather than looking empty. Every path is marked by now, so this
    // cannot ask for the same group twice.
    _rebuildRows();
    for (final node in pending) {
      _loadGroup(node);
    }
  }

  Future<void> _loadGroup(GroupNode<T> node) async {
    final source = _dataSource;
    final pending = query;
    try {
      final children = await source.fetchGroupChildren(pending, node);
      if (isDisposed || source != _dataSource) return;
      _loadedGroups[node.path] = children;
    } on FetchCancelled {
      return;
    } catch (error) {
      if (isDisposed) return;
      // A group that would not load is a failure of this group, not of the
      // grid: the other groups are still good.
      _groupErrors[node.path] = error;
    } finally {
      _loadingGroups.remove(node.path);
      if (!isDisposed) _rebuildRows();
    }
  }

  final Map<String, Object?> _groupErrors = {};

  /// Error from the last attempt to load [path], if it failed.
  Object? groupError(String path) => _groupErrors[path];

  /// Forgets a group's contents so they are fetched again when it is next
  /// open. Called after a write, or by a UI's retry.
  void invalidateGroup(String path) {
    _loadedGroups.remove(path);
    _groupErrors.remove(path);
    _rebuildRows();
  }

  /// Identities of the rows the selection, the active cell and any open edit
  /// are pointing at, keyed by their current index.
  ///
  /// Null when nothing needs tracking - no [rowKey], or nothing selected -
  /// which is what keeps the common refresh free of a scan over every row.
  Map<int, Object>? _trackedRowKeys() {
    final key = rowKey;
    if (key == null) return null;
    final indices = <int>{...selection.rows};
    final active = selection.activeCell;
    if (active != null) indices.add(active.row);
    final anchor = selection.anchor;
    if (anchor != null) indices.add(anchor.row);
    final range = selection.range;
    if (range != null) {
      indices.add(range.anchor.row);
      indices.add(range.focus.row);
    }
    final session = _edit;
    if (session != null) indices.add(session.cell.row);
    if (indices.isEmpty) return null;

    final out = <int, Object>{};
    for (final index in indices) {
      if (index < 0 || index >= _visibleRows.length) continue;
      final row = _visibleRows[index];
      if (row is DataGridRow<T>) out[index] = key(row.data);
    }
    return out.isEmpty ? null : out;
  }

  /// Where each row now sits, by identity.
  Map<Object, int> _rowPositions() {
    final key = rowKey;
    if (key == null) return const {};
    final out = <Object, int>{};
    for (var i = 0; i < _visibleRows.length; i++) {
      final row = _visibleRows[i];
      // First occurrence wins, so a duplicated key degrades to the topmost
      // row rather than to an arbitrary one.
      if (row is DataGridRow<T>) out.putIfAbsent(key(row.data), () => i);
    }
    return out;
  }

  void _onSourceChanged() => refresh();

  // -- Sorting --------------------------------------------------------------

  /// Applies the header-click sort cycle to [field].
  ///
  /// [additive] is the ctrl/cmd-click behaviour that builds a multi-level
  /// sort instead of replacing it.
  void toggleSort(String field, {bool additive = false}) {
    final column = this.column(field);
    if (column == null || !column.sortable) return;
    _sorts = cycleSort(_sorts, field, additive: additive);
    _pageIndex = 0;
    refresh();
  }

  void setSorts(List<SortSpec> sorts) {
    _sorts = List<SortSpec>.of(sorts);
    _pageIndex = 0;
    refresh();
  }

  void clearSorts() => setSorts(const []);

  /// Which sort level [field] occupies, or null when it is unsorted. Adapters
  /// use this to number the arrows in a multi-column sort.
  int? sortPriority(String field) {
    final index = _sorts.indexWhere((s) => s.field == field);
    return index < 0 ? null : index + 1;
  }

  SortSpec? sortFor(String field) =>
      _sorts.where((s) => s.field == field).firstOrNull;

  // -- Filtering ------------------------------------------------------------

  /// Sets the filter row condition for one column. A null or empty condition
  /// clears it.
  void setColumnFilter(String field, FilterCondition? condition) {
    if (condition == null || condition.isEmpty) {
      if (_columnFilters.remove(field) == null) return;
    } else {
      _columnFilters[field] = condition;
    }
    _pageIndex = 0;
    refresh(coalesce: true);
  }

  /// Sets a structured filter that sits alongside the per-column filter row.
  void setFilter(Filter? filter) {
    _filter = filter;
    _pageIndex = 0;
    refresh();
  }

  void clearFilters() {
    if (_filter == null && _columnFilters.isEmpty && _search.isEmpty) return;
    _filter = null;
    _columnFilters.clear();
    _search = '';
    _pageIndex = 0;
    refresh();
  }

  /// Sets the quick-search text applied across filterable columns.
  void setSearch(String text) {
    if (_search == text) return;
    _search = text;
    _pageIndex = 0;
    refresh(coalesce: true);
  }

  // -- Grouping -------------------------------------------------------------

  void groupBy(String field) {
    if (_groups.any((g) => g.field == field)) return;
    final column = this.column(field);
    if (column == null || !column.groupable) return;
    _groups = [..._groups, GroupSpec(field)];
    _pageIndex = 0;
    refresh();
  }

  void setGroups(List<GroupSpec> groups) {
    _groups = List<GroupSpec>.of(groups);
    _pageIndex = 0;
    refresh();
  }

  void ungroup(String field) {
    final next = [
      for (final g in _groups)
        if (g.field != field) g,
    ];
    if (next.length == _groups.length) return;
    setGroups(next);
  }

  void clearGroups() => setGroups(const []);

  /// Opens or closes one group header.
  void toggleGroup(String path) {
    expansion.toggle(path);
    _rebuildRows();
  }

  void setGroupExpanded(String path, bool expanded) {
    expansion.setExpanded(path, expanded);
    _rebuildRows();
  }

  void expandAllGroups() {
    expansion.expandAll();
    _rebuildRows();
  }

  void collapseAllGroups() {
    final result = _result;
    expansion.collapseAll(
      result == null ? const [] : collectGroupPaths<T>(result.groups),
    );
    _rebuildRows();
  }

  /// Re-flattens without re-querying: expansion does not change which rows
  /// matched, only which are on screen.
  void _rebuildRows() {
    final result = _result;
    if (result == null || !result.isGrouped) return;
    _apply(result);
  }

  /// Rebuilds the visible rows from the last result, whatever shape it has.
  void _reapply() {
    final result = _result;
    if (result != null) _apply(result);
  }

  // -- Columns --------------------------------------------------------------

  void setColumns(List<GridColumn<T>> columns) {
    _columns = List<GridColumn<T>>.of(columns);
    _dataSource.columns = columnsByField;
    refresh();
  }

  /// Records an interactive resize, clamped to the column's bounds.
  void resizeColumn(String field, double width) {
    final column = this.column(field);
    if (column == null || !column.resizable) return;
    _columnWidths[field] = column.clampWidth(width);
    notifyListeners();
  }

  /// Widens or narrows [field] to fit its contents, and returns the width it
  /// settled on.
  ///
  /// The engine cannot measure text - that is the one thing it has to ask the
  /// toolkit for - so the caller passes [measure], which returns the width of
  /// a string in logical pixels. In Flutter that is a `TextPainter` with the
  /// cell's own style; the engine samples the rows, formats the values and
  /// takes the widest.
  ///
  /// At most [sampleSize] rows are measured, spread evenly across the view
  /// rather than taken from the top, because the widest value in a 50k-row
  /// column is rarely in the first screenful and measuring all of them is not
  /// affordable. The result is a best fit, not a guarantee: a row that was not
  /// sampled can still be clipped.
  ///
  /// [padding] is added to the measured text for the cell's own insets, and
  /// the result is clamped to the column's [GridColumn.minWidth] and
  /// [GridColumn.maxWidth]. Returns null when there is no such column, or it
  /// is not resizable.
  double? autoSizeColumn(
    String field, {
    required double Function(String text) measure,
    int sampleSize = 200,
    double padding = 24,
    bool includeHeader = true,
  }) {
    final column = this.column(field);
    if (column == null || !column.resizable) return null;

    var widest = includeHeader ? measure(column.title) : 0.0;
    final rows = _visibleRows;
    final step = rows.length <= sampleSize ? 1 : rows.length ~/ sampleSize;
    for (var i = 0; i < rows.length; i += step) {
      final row = rows[i];
      if (row is! DataGridRow<T>) continue;
      final width = measure(column.formattedValue(row.data));
      if (width > widest) widest = width;
    }

    final fitted = column.clampWidth(widest + padding);
    _columnWidths[field] = fitted;
    notifyListeners();
    return fitted;
  }

  /// Fits every visible column, in one notification.
  ///
  /// [measure] is given the column as well as the text, so an adapter can use
  /// each column's own style rather than one style for the grid.
  void autoSizeColumns({
    required double Function(GridColumn<T> column, String text) measure,
    int sampleSize = 200,
    double padding = 24,
    bool includeHeader = true,
  }) {
    final rows = _visibleRows;
    final step = rows.length <= sampleSize ? 1 : rows.length ~/ sampleSize;
    var changed = false;
    for (final column in visibleColumns) {
      if (!column.resizable) continue;
      var widest = includeHeader ? measure(column, column.title) : 0.0;
      for (var i = 0; i < rows.length; i += step) {
        final row = rows[i];
        if (row is! DataGridRow<T>) continue;
        final width = measure(column, column.formattedValue(row.data));
        if (width > widest) widest = width;
      }
      _columnWidths[column.field] = column.clampWidth(widest + padding);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void resetColumnWidth(String field) {
    if (_columnWidths.remove(field) != null) notifyListeners();
  }

  double widthOf(String field) {
    final column = this.column(field);
    if (column == null) return 0;
    return column.clampWidth(_columnWidths[field] ?? column.width);
  }

  void setColumnVisible(String field, bool visible) {
    final index = _columns.indexWhere((c) => c.field == field);
    if (index < 0 || _columns[index].visible == visible) return;
    _columns[index] = _columns[index].copyWith(visible: visible);
    refresh();
  }

  void setColumnPin(String field, ColumnPin pin) {
    final index = _columns.indexWhere((c) => c.field == field);
    if (index < 0 || _columns[index].pin == pin) return;
    _columns[index] = _columns[index].copyWith(pin: pin);
    notifyListeners();
  }

  /// Moves a column to a new position in display order.
  void moveColumn(String field, int newIndex) {
    final from = _columns.indexWhere((c) => c.field == field);
    if (from < 0) return;
    final column = _columns.removeAt(from);
    _columns.insert(newIndex.clamp(0, _columns.length), column);
    notifyListeners();
  }

  /// Header rows spanning several columns, drawn above the column titles,
  /// outermost first.
  List<HeaderRow> get stackedHeaders => List.unmodifiable(_stackedHeaders);

  set stackedHeaders(List<HeaderRow> rows) {
    _stackedHeaders = List<HeaderRow>.of(rows);
    assert(() {
      final problems = describeHeaderProblems<T>(_stackedHeaders, _columns);
      if (problems.isNotEmpty) {
        throw StateError('Stacked headers:\n  ${problems.join('\n  ')}');
      }
      return true;
    }());
    notifyListeners();
  }

  /// Resolves panes and widths for a viewport [width] wide.
  GridLayout<T> layoutFor(double width) => computeLayout<T>(
        _columns,
        viewportWidth: width,
        widthOverrides: _columnWidths,
        fit: columnFit,
      );

  // -- Rows -----------------------------------------------------------------

  GridRow<T>? rowAt(int index) =>
      index < 0 || index >= _visibleRows.length ? null : _visibleRows[index];

  /// The data row at [index], or null when that row is a group header.
  T? dataAt(int index) {
    final row = rowAt(index);
    return row is DataGridRow<T> ? row.data : null;
  }

  /// Data rows currently selected, group headers skipped.
  List<T> get selectedData => [
        for (final index in selection.selectedRows)
          if (dataAt(index) != null) dataAt(index)!,
      ];

  /// Fields in display order, which range selection needs to resolve columns.
  List<String> get visibleFields => [for (final c in visibleColumns) c.field];

  void selectRow(int index,
      [SelectionModifiers modifiers = SelectionModifiers.none]) {
    selection.selectRow(index, modifiers);
    notifyListeners();
  }

  void selectCell(CellAddress cell,
      [SelectionModifiers modifiers = SelectionModifiers.none]) {
    selection.selectCell(cell, visibleFields, modifiers);
    notifyListeners();
  }

  void extendSelectionTo(CellAddress cell) {
    selection.extendTo(cell, visibleFields);
    notifyListeners();
  }

  void selectAllRows() {
    selection.selectAll(_visibleRows.length);
    notifyListeners();
  }

  /// How much of the grid is selected, for a select-all checkbox.
  SelectionCoverage get selectionCoverage =>
      selection.coverageOf(_visibleRows.length);

  /// What a header checkbox should do when tapped.
  ///
  /// Anything short of everything selects the rest; a full selection clears.
  /// That is the behaviour of every spreadsheet and mail client, and it means
  /// the control never needs a separate "deselect all".
  void toggleSelectAll() {
    if (selectionCoverage == SelectionCoverage.all) {
      clearSelection();
    } else {
      selectAllRows();
    }
  }

  /// Selects or deselects one row, leaving the rest alone.
  ///
  /// What a row checkbox does, as distinct from a click on the row, which
  /// replaces the selection.
  void setRowSelected(int index, bool selected) {
    if (selection.isRowSelected(index) == selected) return;
    selection.selectRow(index, SelectionModifiers.toggling);
    notifyListeners();
  }

  void clearSelection() {
    selection.clear();
    notifyListeners();
  }

  /// Moves the active cell by [rowDelta]/[columnDelta], as an arrow key does.
  void moveActiveCell(int rowDelta, int columnDelta, {bool extend = false}) {
    final fields = visibleFields;
    if (fields.isEmpty || _visibleRows.isEmpty) return;
    final current = selection.activeCell;
    final row =
        ((current?.row ?? 0) + rowDelta).clamp(0, _visibleRows.length - 1);
    final columnIndex = current == null
        ? 0
        : (fields.indexOf(current.field) + columnDelta)
            .clamp(0, fields.length - 1);
    final next = CellAddress(row, fields[columnIndex]);
    if (extend) {
      extendSelectionTo(next);
    } else {
      selectCell(next);
    }
  }

  /// Moves the active cell by whole screenfuls, as PageUp and PageDown do.
  ///
  /// [rowsPerPage] comes from the adapter, which is the only side that knows
  /// how many rows the viewport is showing. Negative [pages] moves up.
  void movePages(int pages, {required int rowsPerPage, bool extend = false}) {
    if (rowsPerPage <= 0) return;
    moveActiveCell(pages * rowsPerPage, 0, extend: extend);
  }

  /// Moves the active cell to the first or last column of its row, as Home and
  /// End do.
  void moveToLineEdge({required bool start, bool extend = false}) {
    final fields = visibleFields;
    if (fields.isEmpty || _visibleRows.isEmpty) return;
    final row = selection.activeCell?.row ?? 0;
    final next = CellAddress(row, start ? fields.first : fields.last);
    if (extend) {
      extendSelectionTo(next);
    } else {
      selectCell(next);
    }
  }

  /// Moves the active cell to the very first or very last cell of the grid, as
  /// ctrl-Home and ctrl-End do.
  void moveToGridEdge({required bool start, bool extend = false}) {
    final fields = visibleFields;
    if (fields.isEmpty || _visibleRows.isEmpty) return;
    final next = start
        ? CellAddress(0, fields.first)
        : CellAddress(_visibleRows.length - 1, fields.last);
    if (extend) {
      extendSelectionTo(next);
    } else {
      selectCell(next);
    }
  }

  /// Moves the active cell to the next editable cell in reading order, as Tab
  /// does, and returns where it landed.
  ///
  /// Skips columns that cannot be edited and rows that are group headers,
  /// wrapping to the next row at the end of one. With [wrap] true it also
  /// wraps from the last editable cell round to the first, which is what makes
  /// Tab a way to walk a form; with it false the walk stops at the end and
  /// returns null, leaving the selection where it was.
  ///
  /// Returns null when the grid has no editable cell at all, which is also how
  /// an adapter can tell that Tab should move focus out of the grid instead.
  CellAddress? moveToNextEditableCell({
    bool backwards = false,
    bool wrap = true,
  }) {
    final fields = [
      for (final column in visibleColumns)
        if (column.editable) column.field,
    ];
    if (fields.isEmpty || _visibleRows.isEmpty) return null;

    final current = selection.activeCell;
    final all = visibleFields;
    var row = current?.row ?? 0;
    // Where in the editable fields the active cell sits. A cell in a column
    // that is not editable still has a place in the order: the next editable
    // column to its right.
    var slot = current == null ? -1 : fields.indexOf(current.field);
    if (current != null && slot < 0) {
      final at = all.indexOf(current.field);
      slot = -1;
      for (var i = 0; i < fields.length; i++) {
        if (all.indexOf(fields[i]) < at) slot = i;
      }
    }

    final step = backwards ? -1 : 1;
    final total = _visibleRows.length * fields.length;
    for (var moved = 0; moved < total; moved++) {
      slot += step;
      if (slot >= fields.length) {
        slot = 0;
        row++;
      } else if (slot < 0) {
        slot = fields.length - 1;
        row--;
      }
      if (row >= _visibleRows.length) {
        if (!wrap) return null;
        row = 0;
      } else if (row < 0) {
        if (!wrap) return null;
        row = _visibleRows.length - 1;
      }
      if (dataAt(row) == null) continue;
      final next = CellAddress(row, fields[slot]);
      selectCell(next);
      return next;
    }
    return null;
  }

  // -- Frozen rows ----------------------------------------------------------

  /// Rows pinned to the top of the viewport, taken from the start of
  /// [visibleRows].
  ///
  /// Freezing is by position rather than by identity, which is what makes it
  /// useful: pin two rows and sort, and the pinned rows are whatever now
  /// sorts first. A row pinned by identity would instead jump around, which
  /// is the opposite of what the name promises.
  int get frozenRowCount => _frozenRowCount;

  set frozenRowCount(int value) {
    final clamped = value < 0 ? 0 : value;
    if (clamped == _frozenRowCount) return;
    _frozenRowCount = clamped;
    notifyListeners();
  }

  /// Rows pinned to the bottom of the viewport, taken from the end of
  /// [visibleRows]. A totals row usually lives here.
  int get frozenRowCountBottom => _frozenRowCountBottom;

  set frozenRowCountBottom(int value) {
    final clamped = value < 0 ? 0 : value;
    if (clamped == _frozenRowCountBottom) return;
    _frozenRowCountBottom = clamped;
    notifyListeners();
  }

  /// How many rows are actually frozen at the top, once the row count is
  /// taken into account.
  ///
  /// Freezing more rows than exist would leave nothing to scroll, so the two
  /// frozen bands together are capped at one row fewer than the grid has.
  int get effectiveFrozenTop {
    if (_frozenRowCount <= 0 || rowCount == 0) return 0;
    return _frozenRowCount > rowCount - 1 ? rowCount - 1 : _frozenRowCount;
  }

  /// How many rows are actually frozen at the bottom. The top band wins when
  /// the two would overlap, because it is the one the user is looking at.
  int get effectiveFrozenBottom {
    if (_frozenRowCountBottom <= 0 || rowCount == 0) return 0;
    final room = rowCount - effectiveFrozenTop - 1;
    if (room <= 0) return 0;
    return _frozenRowCountBottom > room ? room : _frozenRowCountBottom;
  }

  /// The rows pinned to the top, in display order.
  List<GridRow<T>> get frozenTopRows =>
      _visibleRows.sublist(0, effectiveFrozenTop);

  /// The rows pinned to the bottom, in display order.
  List<GridRow<T>> get frozenBottomRows =>
      _visibleRows.sublist(_visibleRows.length - effectiveFrozenBottom);

  /// The rows that actually scroll, between the two frozen bands.
  List<GridRow<T>> get scrollableRows => _visibleRows.sublist(
        effectiveFrozenTop,
        _visibleRows.length - effectiveFrozenBottom,
      );

  /// Whether the row at [index] in [visibleRows] is frozen.
  bool isRowFrozen(int index) =>
      index < effectiveFrozenTop ||
      index >= _visibleRows.length - effectiveFrozenBottom;

  // -- Conditional formatting -----------------------------------------------

  /// Range of the values currently shown in [field].
  ///
  /// A result that carries stats for the column wins: a remote source knows
  /// the range over the whole filtered set, while the grid only holds the
  /// page it was sent.
  ColumnStats statsFor(String field) =>
      _result?.stats[field] ?? _dataSource.statsFor(field);

  /// The distinct values of [field] among the matching rows, for a checkbox
  /// filter list. Empty when the source cannot answer.
  List<Object?> distinctValuesFor(String field, {int limit = 500}) =>
      _dataSource.distinctValuesFor(field, limit: limit);

  /// The filter operators worth offering for [field], most useful first.
  ///
  /// Resolved from the column's [ColumnType], so an adapter builds its menu
  /// from the engine's model of the column instead of its own switch.
  List<FilterOperator> operatorsForField(String field) {
    final column = this.column(field);
    return column == null ? const [] : operatorsFor(column.type);
  }

  /// How the cell at [field] in [row] should be emphasised.
  ///
  /// Returns [CellDecoration.none] when the column has no rule, so an adapter
  /// can call this for every visible cell without a null check and without
  /// paying for columns that are not formatted.
  CellDecoration decorationFor(String field, T row) {
    final column = this.column(field);
    final rule = column?.rule;
    if (column == null || rule == null) return CellDecoration.none;
    return rule.decorate(column.value(row), statsFor(field)) ??
        CellDecoration.none;
  }

  // -- Editing --------------------------------------------------------------

  /// Opens an edit session, if the cell is editable. Returns null otherwise.
  ///
  /// A cell is editable when its column has a setter *and* the data source can
  /// write rows back. Refusing at the door is deliberate: an editor the grid
  /// cannot save is a worse outcome than no editor, because the user only
  /// finds out after typing.
  EditSession<T>? beginEdit(CellAddress cell) {
    final column = this.column(cell.field);
    final data = dataAt(cell.row);
    if (column == null || data == null || !column.editable) return null;
    if (!_dataSource.canCommit) return null;
    _edit = EditSession<T>(
      cell: cell,
      column: column,
      row: data,
      initialValue: column.value(data),
    );
    notifyListeners();
    return _edit;
  }

  /// Updates the in-flight value, re-running validation.
  void updateEdit(Object? value) {
    _edit?.update(value);
    notifyListeners();
  }

  /// Validates and writes the edit back through [LatticeDataSource.commit].
  ///
  /// A rejected edit keeps the session open with its error set, so the user
  /// can correct the value instead of losing it.
  ///
  /// The write itself is asynchronous, because a remote source has a round
  /// trip to make, and this returns as soon as the value has passed
  /// validation. The new value is on screen from that moment: it is held as a
  /// pending write and substituted into whatever the source returns next, so
  /// the re-fetch that follows a write cannot show the old value again. If the
  /// write throws, the pending value is dropped - the cell goes back to what
  /// the source holds - and the reason appears in [writeError]. Await
  /// [pendingWrite] to observe the outcome.
  EditResult<T> commitEdit() {
    final session = _edit;
    if (session == null) return const EditResult<Never>.cancelled();
    final result = session.commit();
    if (result.isRejected) {
      notifyListeners();
      return result;
    }
    _edit = null;
    final row = result.row;
    if (row == null) {
      notifyListeners();
      return result;
    }
    if (session.value != session.originalValue) {
      _history.record(EditAction<T>(
        label: 'Edit ${session.column.title}',
        changes: [
          CellEdit<T>(
            row: row,
            field: session.cell.field,
            before: session.originalValue,
            after: session.value,
          ),
        ],
      ));
    }
    _pendingWrite = _write(session.row, row);
    return result;
  }

  /// Rows written but not yet confirmed by the source, keyed by identity.
  final Map<Object, T> _pendingWrites = {};
  Object? _writeError;
  Future<void>? _pendingWrite;

  /// Whether an edit has been committed and not yet confirmed by the source.
  bool get hasPendingWrites => _pendingWrites.isNotEmpty;

  /// Error thrown by the last write, if it failed.
  ///
  /// Distinct from [error], which is a failed fetch: a rejected write leaves
  /// the rows on screen intact and only means one value did not save.
  Object? get writeError => _writeError;

  void clearWriteError() {
    if (_writeError == null) return;
    _writeError = null;
    notifyListeners();
  }

  /// The write in flight, for tests and for a UI that wants to await it.
  Future<void>? get pendingWrite => _pendingWrite;

  /// Whether cells can be edited at all, i.e. the source can write rows back.
  bool get canEdit => _dataSource.canCommit;

  /// Identity used to match a pending write to a fetched row.
  ///
  /// Falls back to the row object itself when there is no [rowKey], which is
  /// right for a source that hands back the same instances and is the reason
  /// an immutable model wants a [rowKey].
  Object _identityOf(T row) => rowKey?.call(row) ?? row as Object;

  T _substituteWrite(T row) => _pendingWrites[_identityOf(row)] ?? row;

  Future<void> _write(T original, T updated) =>
      _writeAll([RowUpdate<T>(original, updated)]);

  /// Sends committed rows to the source, showing them immediately and rolling
  /// them back if the source refuses them.
  ///
  /// One call is one change: a paste across twenty rows goes down as a single
  /// batch and the grid re-queries once, because twenty write-through
  /// refreshes would also be twenty re-sorts.
  Future<void> _writeAll(List<RowUpdate<T>> writes) async {
    if (writes.isEmpty) return;
    final source = _dataSource;
    if (!source.canCommit) {
      // beginEdit refuses a read-only source, so reaching this means the
      // source was swapped mid-edit.
      _writeError = UnsupportedError(
        '${source.runtimeType} cannot save edits.',
      );
      notifyListeners();
      return;
    }

    if (source.isLocal) {
      // A local source answers synchronously and its own write-through
      // refresh already shows the new values; an overlay would only buy a
      // second rebuild.
      try {
        await source.commitAll(writes);
      } catch (error) {
        if (isDisposed) return;
        _writeError = error;
        notifyListeners();
      }
      return;
    }

    final keys = [for (final write in writes) _identityOf(write.original)];
    for (var i = 0; i < writes.length; i++) {
      _pendingWrites[keys[i]] = writes[i].updated;
    }
    _writeError = null;
    _reapply();
    try {
      final stored = await source.commitAll(writes);
      if (isDisposed) return;
      // The source may have normalised the values; show what it returned.
      for (var i = 0; i < keys.length && i < stored.length; i++) {
        _pendingWrites[keys[i]] = stored[i];
      }
      // Re-query, so an edit that changed a sort or filter key moves its row.
      // The pending values cover the gap until the source's own copies carry
      // them.
      await refresh();
      if (isDisposed) return;
      keys.forEach(_pendingWrites.remove);
      _reapply();
    } catch (error) {
      if (isDisposed) return;
      keys.forEach(_pendingWrites.remove);
      _writeError = error;
      _reapply();
    }
  }

  // -- Paste ----------------------------------------------------------------

  /// Writes clipboard text into the grid, starting at [at] or at the active
  /// cell.
  ///
  /// The inverse of [copySelectionAsText]: the text is split into rows and
  /// cells, each cell is parsed into its column's type by [coerceValue] and
  /// put through that column's validator, and the result is written as one
  /// change that one [undo] takes back.
  ///
  /// Columns are filled rightwards from the target in screen order and rows
  /// downwards. A block that runs past the edge of the grid is clipped rather
  /// than growing it - the engine has no way to invent a row of `T` - and
  /// [PasteResult.cellsClipped] says how much was left out.
  ///
  /// With [allOrNothing] true, the default, a single bad cell writes nothing:
  /// half a pasted block is harder to recover from than none of it, because
  /// the user cannot see where it stopped. Pass false to write what fits and
  /// read [PasteResult.rejections] for the rest.
  PasteResult pasteText(
    String text, {
    CellAddress? at,
    bool allOrNothing = true,
    String delimiter = '\t',
  }) {
    final target = at ?? selection.activeCell;
    if (target == null) return const PasteResult.noTarget();
    if (!_dataSource.canCommit) {
      return PasteResult(
        rejections: [
          PasteRejection(
            cell: target,
            text: text,
            reason: '${_dataSource.runtimeType} cannot save edits',
          ),
        ],
      );
    }

    final block = parseClipboardText(text, delimiter: delimiter);
    if (block.isEmpty) return const PasteResult();

    final fields = visibleFields;
    final firstColumn = fields.indexOf(target.field);
    if (firstColumn < 0) return const PasteResult.noTarget();

    final byField = columnsByField;
    final rejections = <PasteRejection>[];
    final changes = <CellEdit<T>>[];
    // Several cells can land in one row, and that row has to be written once,
    // with all of them applied.
    final patches = <_RowPatch<T>>[];
    final slots = <Object, int>{};
    var clipped = 0;

    for (var r = 0; r < block.length; r++) {
      final rowIndex = target.row + r;
      final data = dataAt(rowIndex);
      if (data == null) {
        clipped += block[r].length;
        continue;
      }
      final identity = _identityOf(data);
      for (var c = 0; c < block[r].length; c++) {
        final columnIndex = firstColumn + c;
        if (columnIndex >= fields.length) {
          clipped++;
          continue;
        }
        final field = fields[columnIndex];
        final column = byField[field];
        final cell = CellAddress(rowIndex, field);
        final raw = block[r][c];
        if (column == null || !column.editable) {
          rejections.add(PasteRejection(
            cell: cell,
            text: raw,
            reason: 'Column is not editable',
          ));
          continue;
        }
        final value = coerceValue(raw, column.type);
        if (value == null && raw.trim().isNotEmpty) {
          rejections.add(PasteRejection(
            cell: cell,
            text: raw,
            reason: 'Not a ${column.type.name}',
          ));
          continue;
        }
        final error = column.validator?.call(value);
        if (error != null) {
          rejections.add(PasteRejection(cell: cell, text: raw, reason: error));
          continue;
        }
        final before = column.value(data);
        if (before == value) continue;
        var slot = slots[identity];
        if (slot == null) {
          slot = patches.length;
          slots[identity] = slot;
          patches.add(_RowPatch<T>(data));
        }
        patches[slot].values[field] = value;
        changes.add(CellEdit<T>(
          row: data,
          field: field,
          before: before,
          after: value,
        ));
      }
    }

    if (rejections.isNotEmpty && allOrNothing) {
      return PasteResult(
        cellsClipped: clipped,
        rejections: rejections,
      );
    }
    if (changes.isEmpty) {
      return PasteResult(cellsClipped: clipped, rejections: rejections);
    }

    _history.record(EditAction<T>(label: 'Paste', changes: changes));
    _pendingWrite = _writeAll(_updatesFor(patches));
    notifyListeners();
    return PasteResult(
      rowsChanged: patches.length,
      cellsChanged: changes.length,
      cellsClipped: clipped,
      rejections: rejections,
      applied: true,
    );
  }

  List<RowUpdate<T>> _updatesFor(List<_RowPatch<T>> patches) => [
        for (final patch in patches)
          RowUpdate<T>(patch.row, _withValues(patch.row, patch.values)),
      ];

  /// Applies several cell values to one row, through the columns' setters.
  ///
  /// A setter that returns null has mutated the row in place, so the chain
  /// carries on with the row it was given.
  T _withValues(T row, Map<String, Object?> values) {
    var updated = row;
    for (final entry in values.entries) {
      final setValue = column(entry.key)?.setValue;
      if (setValue == null) continue;
      updated = setValue(updated, entry.value) ?? updated;
    }
    return updated;
  }

  // -- Undo and redo --------------------------------------------------------

  final EditHistory<T> _history = EditHistory<T>();

  /// Undo and redo over committed edits.
  ///
  /// Read it for [EditHistory.canUndo] and the labels of the next steps; call
  /// [undo] and [redo] rather than its own take methods, so the change is
  /// actually written back.
  EditHistory<T> get history => _history;

  /// Takes back the last committed edit or paste, as one step.
  ///
  /// Returns false when there is nothing to undo, or when the rows an action
  /// touched can no longer be found - deleted, or filtered out of the current
  /// view. Finding them needs either a [rowKey] or a row model whose setter
  /// mutates in place; an immutable model without a key cannot be matched to
  /// the instances the source now holds.
  bool undo() => _replay(_history.takeUndo()?.inverse);

  /// Re-applies the edit [undo] took back.
  bool redo() => _replay(_history.takeRedo());

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  bool _replay(EditAction<T>? action) {
    if (action == null || action.isEmpty) return false;
    final patches = <_RowPatch<T>>[];
    final slots = <Object, int>{};

    for (final change in action.changes) {
      final current = _currentRowFor(change.row);
      if (current == null) continue;
      final identity = _identityOf(current);
      var slot = slots[identity];
      if (slot == null) {
        slot = patches.length;
        slots[identity] = slot;
        patches.add(_RowPatch<T>(current));
      }
      patches[slot].values[change.field] = change.after;
    }
    if (patches.isEmpty) return false;

    _pendingWrite = _writeAll(_updatesFor(patches));
    notifyListeners();
    return true;
  }

  /// The instance the grid currently holds for [row], matched by [rowKey]
  /// where there is one.
  T? _currentRowFor(T row) {
    final key = rowKey;
    if (key == null) return row;
    final wanted = key(row);
    for (final visible in _visibleRows) {
      if (visible is DataGridRow<T> && key(visible.data) == wanted) {
        return visible.data;
      }
    }
    return null;
  }

  void cancelEdit() {
    if (_edit == null) return;
    _edit!.cancel();
    _edit = null;
    notifyListeners();
  }

  bool isEditing(CellAddress cell) => _edit?.cell == cell;

  // -- Export ---------------------------------------------------------------

  /// Exports the current view as CSV, matching what is on screen.
  ///
  /// Columns are written in screen order, so a pinned column exports where
  /// the user sees it. Pass [ExportOptions.fields] to override that.
  String exportCsv({ExportOptions options = const ExportOptions()}) {
    final exporter = CsvExporter<T>(
      options.fields == null ? visibleColumns : _columns,
      options: options,
    );
    final result = _result;
    if (result == null) return '';
    return exporter.exportResult(result, expansion);
  }

  /// Copies the selected range (or rows) as tab-separated clipboard text.
  String copySelectionAsText({bool includeHeader = false}) {
    final fields = visibleFields;
    final byField = columnsByField;
    final rows = <List<String>>[];
    final range = selection.range;

    List<String> cellsFor(int rowIndex, List<String> fieldSet) {
      final data = dataAt(rowIndex);
      if (data == null) return List.filled(fieldSet.length, '');
      return [for (final f in fieldSet) byField[f]?.formattedValue(data) ?? ''];
    }

    if (range != null) {
      final covered = range.coveredFields;
      if (includeHeader) {
        rows.add([for (final f in covered) byField[f]?.title ?? f]);
      }
      for (var r = range.firstRow; r <= range.lastRow; r++) {
        rows.add(cellsFor(r, covered));
      }
    } else {
      if (includeHeader) {
        rows.add([for (final f in fields) byField[f]?.title ?? f]);
      }
      for (final index in selection.selectedRows) {
        rows.add(cellsFor(index, fields));
      }
    }
    return toClipboardText<T>(rows);
  }

  // -- Saved views ----------------------------------------------------------

  /// The current arrangement, ready to be stored as JSON.
  ///
  /// Covers everything the user set: the ordering, the filters and the search,
  /// the grouping and which groups they closed, the page, and the column
  /// widths, order, pinning and visibility. What it cannot cover is code - an
  /// [Aggregation]'s reducer, a column's accessors, a [GroupSpec]'s bucketing
  /// functions - which stay with the definitions the grid is built from.
  GridViewState saveState() {
    return GridViewState(
      sorts: _sorts,
      filter: _filter,
      columnFilters: Map<String, FilterCondition>.of(_columnFilters),
      search: _search,
      groups: _groups,
      collapsedGroupPaths: expansion.overrides.toList(),
      columns: [
        for (final c in _columns)
          ColumnViewState(
            field: c.field,
            // Only a width the user actually dragged.
            width: _columnWidths[c.field],
            visible: c.visible,
            pin: c.pin,
          ),
      ],
      pageIndex: _pageIndex,
      pageSize: _pageSize,
      frozenRowCount: _frozenRowCount,
      frozenRowCountBottom: _frozenRowCountBottom,
      columnFit: columnFit,
    );
  }

  /// Applies a saved arrangement and re-queries once.
  ///
  /// Columns in the view that the grid does not have are ignored, and columns
  /// the grid has that the view does not know about keep their definitions and
  /// follow the restored ones - so a view saved before a column was added
  /// still restores, with the new column at the end.
  ///
  /// [resolveGroup] is given each restored [GroupSpec] and returns the one to
  /// use, which is how a grouping with a `keyOf` survives the round trip: the
  /// JSON remembers the field, your code supplies the function.
  void restoreState(
    GridViewState state, {
    GroupSpec Function(GroupSpec restored)? resolveGroup,
  }) {
    if (state.columns.isNotEmpty) {
      final byField = {for (final c in _columns) c.field: c};
      final restored = <GridColumn<T>>[];
      _columnWidths.clear();
      for (final saved in state.columns) {
        final column = byField.remove(saved.field);
        if (column == null) continue;
        restored.add(column.copyWith(visible: saved.visible, pin: saved.pin));
        final width = saved.width;
        if (width != null) _columnWidths[saved.field] = width;
      }
      // Columns the view never saw keep their place relative to each other.
      for (final column in _columns) {
        if (byField.containsKey(column.field)) restored.add(column);
      }
      _columns = restored;
      _dataSource.columns = columnsByField;
    }

    _sorts = List<SortSpec>.of(state.sorts);
    _filter = state.filter;
    _columnFilters
      ..clear()
      ..addAll(state.columnFilters);
    _search = state.search;
    _groups = [
      for (final g in state.groups) resolveGroup == null ? g : resolveGroup(g),
    ];
    expansion.setOverrides(state.collapsedGroupPaths);
    _pageSize = state.pageSize;
    _pageIndex = state.pageIndex < 0 ? 0 : state.pageIndex;
    _frozenRowCount = state.frozenRowCount;
    _frozenRowCountBottom = state.frozenRowCountBottom;
    columnFit = state.columnFit;
    // One query for the whole restore: setting these one at a time would send
    // a request per property.
    refresh();
  }

  /// Swaps the data source, e.g. from a local list to a server-backed one.
  void setDataSource(LatticeDataSource<T> source) {
    _dataSource.removeListener(_onSourceChanged);
    _dataSource = source;
    _dataSource.columns = columnsByField;
    _dataSource.addListener(_onSourceChanged);
    _pageIndex = 0;
    refresh();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _cancelFetch('the grid was disposed');
    _dataSource.removeListener(_onSourceChanged);
    super.dispose();
  }
}

/// A row and the cell values bound for it.
///
/// A paste or an undo can touch several cells of the same row, and the row
/// has to be written once with all of them applied - not once per cell.
class _RowPatch<T> {
  _RowPatch(this.row);

  final T row;
  final Map<String, Object?> values = {};
}
