/// The grid's single source of truth.
library;

import 'aggregate.dart';
import 'column.dart';
import 'data_source.dart';
import 'decoration.dart';
import 'editing.dart';
import 'export.dart';
import 'filter.dart';
import 'group.dart';
import 'layout.dart';
import 'notifier.dart';
import 'query.dart';
import 'rows.dart';
import 'selection.dart';
import 'sort.dart';
import 'stacked_header.dart';

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
    );
  }

  /// Re-runs the query and rebuilds [visibleRows].
  ///
  /// Concurrent fetches are token-guarded, so a slow response from an earlier
  /// query can never overwrite the result of a newer one.
  Future<void> refresh() async {
    final token = ++_fetchToken;
    final source = _dataSource;

    // A local source answers synchronously; resolving it inline avoids a
    // frame of empty grid on the very first build.
    if (source is InMemoryDataSource<T>) {
      _loading = false;
      _error = null;
      _apply(source.fetchSync(query));
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await source.fetch(query);
      if (token != _fetchToken || isDisposed) return;
      _loading = false;
      _apply(result);
    } catch (error) {
      if (token != _fetchToken || isDisposed) return;
      _loading = false;
      _error = error;
      _visibleRows = const [];
      notifyListeners();
    }
  }

  void _apply(GridResult<T> result) {
    // Read the identities the user is pointing at before the rows change
    // under them.
    final tracked = _trackedRowKeys();

    _result = result;
    _visibleRows = result.isGrouped
        ? flattenGroups<T>(result.groups, expansion)
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
    refresh();
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
    refresh();
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
  ColumnStats statsFor(String field) => _dataSource.statsFor(field);

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

  /// Sends a committed row to the source, showing it immediately and rolling
  /// it back if the source refuses it.
  Future<void> _write(T original, T updated) async {
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
      // refresh already shows the new value; an overlay would only buy a
      // second rebuild.
      try {
        await source.commit(original, updated);
      } catch (error) {
        if (isDisposed) return;
        _writeError = error;
        notifyListeners();
      }
      return;
    }

    final key = _identityOf(original);
    _pendingWrites[key] = updated;
    _writeError = null;
    _reapply();
    try {
      final stored = await source.commit(original, updated);
      if (isDisposed) return;
      // The source may have normalised the value; show what it returned.
      _pendingWrites[key] = stored;
      // Re-query, so an edit that changed a sort or filter key moves its row.
      // The pending value covers the gap until the source's own copy of the
      // row carries it.
      await refresh();
      if (isDisposed) return;
      _pendingWrites.remove(key);
      _reapply();
    } catch (error) {
      if (isDisposed) return;
      _pendingWrites.remove(key);
      _writeError = error;
      _reapply();
    }
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
    _dataSource.removeListener(_onSourceChanged);
    super.dispose();
  }
}
