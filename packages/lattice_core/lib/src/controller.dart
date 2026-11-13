/// The grid's single source of truth.
library;

import 'aggregate.dart';
import 'column.dart';
import 'data_source.dart';
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
    int? pageSize,
    bool groupsExpandedByDefault = true,
    this.columnFit = ColumnFit.none,
  })  : _columns = List<GridColumn<T>>.of(columns),
        _dataSource = dataSource,
        _sorts = List<SortSpec>.of(sorts),
        _groups = List<GroupSpec>.of(groups),
        _aggregations = List<Aggregation>.of(aggregations),
        _filter = filter,
        _pageSize = pageSize,
        selection = SelectionState(mode: selectionMode),
        expansion = GroupExpansionState(expandedByDefault: groupsExpandedByDefault) {
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

  // -- Read-only view of the state ------------------------------------------

  List<GridColumn<T>> get columns => List.unmodifiable(_columns);

  /// Columns taking part in layout, in display order.
  List<GridColumn<T>> get visibleColumns => [
        for (final c in _columns)
          if (c.visible) c,
      ];

  Map<String, GridColumn<T>> get columnsByField =>
      {for (final c in _columns) c.field: c};

  GridColumn<T>? column(String field) =>
      _columns.where((c) => c.field == field).firstOrNull;

  LatticeDataSource<T> get dataSource => _dataSource;

  List<SortSpec> get sorts => List.unmodifiable(_sorts);
  List<GroupSpec> get groups => List.unmodifiable(_groups);
  List<Aggregation> get aggregations => List.unmodifiable(_aggregations);
  Filter? get filter => _filter;
  Map<String, FilterCondition> get columnFilters => Map.unmodifiable(_columnFilters);
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
          : (conditions.length == 1 ? conditions.first : FilterGroup.and(conditions)),
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
    _result = result;
    _visibleRows = result.isGrouped
        ? flattenGroups<T>(result.groups, expansion)
        : [
            for (var i = 0; i < result.rows.length; i++)
              DataGridRow<T>(
                index: i,
                data: result.rows[i],
                sourceIndex: query.offset + i,
              ),
          ];
    selection.clampTo(_visibleRows.length);
    notifyListeners();
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

  void selectRow(int index, [SelectionModifiers modifiers = SelectionModifiers.none]) {
    selection.selectRow(index, modifiers);
    notifyListeners();
  }

  void selectCell(CellAddress cell, [SelectionModifiers modifiers = SelectionModifiers.none]) {
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

  void clearSelection() {
    selection.clear();
    notifyListeners();
  }

  /// Moves the active cell by [rowDelta]/[columnDelta], as an arrow key does.
  void moveActiveCell(int rowDelta, int columnDelta, {bool extend = false}) {
    final fields = visibleFields;
    if (fields.isEmpty || _visibleRows.isEmpty) return;
    final current = selection.activeCell;
    final row = ((current?.row ?? 0) + rowDelta).clamp(0, _visibleRows.length - 1);
    final columnIndex = current == null
        ? 0
        : (fields.indexOf(current.field) + columnDelta).clamp(0, fields.length - 1);
    final next = CellAddress(row, fields[columnIndex]);
    if (extend) {
      extendSelectionTo(next);
    } else {
      selectCell(next);
    }
  }

  // -- Editing --------------------------------------------------------------

  /// Opens an edit session, if the cell is editable. Returns null otherwise.
  EditSession<T>? beginEdit(CellAddress cell) {
    final column = this.column(cell.field);
    final data = dataAt(cell.row);
    if (column == null || data == null || !column.editable) return null;
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

  /// Validates and writes the edit back to the source.
  ///
  /// A rejected edit keeps the session open with its error set, so the user
  /// can correct the value instead of losing it.
  EditResult<T> commitEdit() {
    final session = _edit;
    if (session == null) return const EditResult<Never>.cancelled();
    final result = session.commit();
    if (result.isRejected) {
      notifyListeners();
      return result;
    }
    _edit = null;
    final source = _dataSource;
    final row = result.row;
    if (row != null && source is InMemoryDataSource<T>) {
      final sourceRows = source.rows;
      final index = sourceRows.indexOf(session.row);
      if (index >= 0) {
        // Writes through the source, which notifies and re-runs the query, so
        // an edit that changes the sort key moves the row immediately.
        source.replaceAt(index, row);
        return result;
      }
    }
    source.invalidate();
    return result;
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
  String exportCsv({ExportOptions options = const ExportOptions()}) {
    final exporter = CsvExporter<T>(_columns, options: options);
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
