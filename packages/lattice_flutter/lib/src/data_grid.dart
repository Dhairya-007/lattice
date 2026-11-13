import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:material_ui/material_ui.dart';

import 'grid_cell.dart';
import 'grid_header.dart';
import 'group_row.dart';
import 'pager.dart';
import 'synced_scroll.dart';
import 'theme.dart';

/// A virtualized data grid.
///
/// All behaviour lives in the [GridController] from `lattice_core`; this
/// widget renders its current state and turns gestures and keys back into
/// controller calls. That split is deliberate: it is what keeps grid
/// behaviour unit-testable and what lets other frameworks reuse the engine.
///
/// ```dart
/// LatticeDataGrid<Employee>(
///   controller: controller,
///   showFilterRow: true,
///   onRowTap: (row) => open(row.data),
/// )
/// ```
class LatticeDataGrid<T> extends StatefulWidget {
  const LatticeDataGrid({
    required this.controller,
    this.theme,
    this.showHeader = true,
    this.showFilterRow = false,
    this.showFooter = true,
    this.rowHeight,
    this.rowHeightBuilder,
    this.cellBuilder,
    this.onRowTap,
    this.onRowDoubleTap,
    this.onCellTap,
    this.emptyState,
    this.loadingState,
    this.errorBuilder,
    this.pageSizes = const [25, 50, 100, 250],
    this.autofocus = false,
    this.editOnDoubleTap = true,
    this.stickyGroupHeaders = true,
    this.highlightChanges = false,
    this.rowId,
    super.key,
  });

  final GridController<T> controller;

  /// Visuals; defaults to [LatticeGridTheme.of].
  final LatticeGridTheme? theme;

  final bool showHeader;

  /// Shows a row of per-column filter inputs under the header.
  final bool showFilterRow;

  final bool showFooter;

  /// Uniform row height; defaults to the theme's.
  final double? rowHeight;

  /// Per-row height. Supplying this disables the uniform fast path, so prefer
  /// [rowHeight] unless rows genuinely differ.
  final double Function(GridRow<T> row)? rowHeightBuilder;

  /// Replaces the default cell content.
  final GridCellBuilder<T>? cellBuilder;

  final void Function(DataGridRow<T> row)? onRowTap;
  final void Function(DataGridRow<T> row)? onRowDoubleTap;
  final void Function(CellAddress cell, T row)? onCellTap;

  /// Shown when the query matched nothing.
  final Widget? emptyState;

  /// Shown while an async source is in flight and no rows are known yet.
  final Widget? loadingState;

  /// Shown when a fetch failed.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  final List<int> pageSizes;

  /// Whether the grid takes keyboard focus on first build.
  final bool autofocus;

  /// Whether a double tap opens the editor on an editable cell.
  final bool editOnDoubleTap;

  /// Pins the current group's header to the top of the viewport while
  /// scrolling inside that group, so it is always clear which group the rows
  /// on screen belong to.
  final bool stickyGroupHeaders;

  /// Flashes a cell when its value changes, for live data.
  ///
  /// Requires [rowId]: without a stable identity, a row scrolling into a
  /// position cannot be told from a value changing, and the grid would
  /// flash on every scroll.
  final bool highlightChanges;

  /// A stable identity for a row, used by [highlightChanges].
  final Object Function(T row)? rowId;

  @override
  State<LatticeDataGrid<T>> createState() => _LatticeDataGridState<T>();
}

class _LatticeDataGridState<T> extends State<LatticeDataGrid<T>> {
  /// One vertical controller per pane, locked together.
  late final SyncedScrollGroup _vertical;

  /// Header and body scroll horizontally as one.
  late final SyncedScrollGroup _horizontal;

  late final ScrollController _vLeading;
  late final ScrollController _vScrolling;
  late final ScrollController _vTrailing;
  late final ScrollController _hHeader;
  late final ScrollController _hBody;

  final FocusNode _focus = FocusNode(debugLabel: 'LatticeDataGrid');

  int? _hoveredRow;
  CellAddress? _lastTapCell;
  DateTime? _lastTapAt;

  @override
  void initState() {
    super.initState();
    _vertical = SyncedScrollGroup();
    _vLeading = _vertical.addAndGet();
    _vScrolling = _vertical.addAndGet();
    _vTrailing = _vertical.addAndGet();
    _horizontal = SyncedScrollGroup();
    _hHeader = _horizontal.addAndGet();
    _hBody = _horizontal.addAndGet();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(LatticeDataGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _vertical.dispose();
    _horizontal.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  GridController<T> get _controller => widget.controller;

  double get _rowHeight => widget.rowHeight ?? _effectiveTheme.rowHeight;

  LatticeGridTheme get _effectiveTheme =>
      widget.theme ?? LatticeGridTheme.of(context);

  double _heightOf(int index) {
    final builder = widget.rowHeightBuilder;
    if (builder == null) return _rowHeight;
    final row = _controller.rowAt(index);
    return row == null ? _rowHeight : builder(row);
  }

  // -- Keyboard -------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final shift = keyboard.isShiftPressed;
    final meta = keyboard.isControlPressed || keyboard.isMetaPressed;
    final key = event.logicalKey;

    if (meta && key == LogicalKeyboardKey.keyA) {
      _controller.selectAllRows();
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyC) {
      final text = _controller.copySelectionAsText();
      if (text.isNotEmpty) Clipboard.setData(ClipboardData(text: text));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, 0, extend: shift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, 0, extend: shift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _move(0, 1, extend: shift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _move(0, -1, extend: shift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _move(0, shift ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.pageUp) {
      final rows = (_vertical.viewportExtent / _rowHeight).floor();
      _move(
        key == LogicalKeyboardKey.pageDown ? rows : -rows,
        0,
        extend: shift,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
      final target = key == LogicalKeyboardKey.home
          ? 0
          : _controller.rowCount - 1;
      final current = _controller.selection.activeCell?.row ?? 0;
      _move(target - current, 0, extend: shift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      final active = _controller.selection.activeCell;
      if (active != null) {
        _controller.selectRow(active.row, SelectionModifiers.toggling);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.f2) {
      final active = _controller.selection.activeCell;
      if (active != null) _controller.beginEdit(active);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _controller.cancelEdit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int rowDelta, int columnDelta, {bool extend = false}) {
    _controller.moveActiveCell(rowDelta, columnDelta, extend: extend);
    final active = _controller.selection.activeCell;
    if (active != null) _revealRow(active.row);
  }

  /// Scrolls the row into view, moving as little as possible.
  void _revealRow(int index) {
    if (!_vScrolling.hasClients) return;
    final metrics = widget.rowHeightBuilder == null
        ? RowMetrics.uniform(
            rowCount: _controller.rowCount,
            rowHeight: _rowHeight,
          )
        : RowMetrics.variable(
            rowCount: _controller.rowCount,
            heightOf: _heightOf,
          );
    final target = metrics.scrollOffsetToReveal(
      index,
      viewportExtent: _vScrolling.position.viewportDimension,
      currentOffset: _vScrolling.offset,
    );
    if (target != _vScrolling.offset) _vertical.jumpTo(target);
  }

  // -- Gestures -------------------------------------------------------------

  void _handleCellTap(CellAddress cell) {
    _focus.requestFocus();
    final keyboard = HardwareKeyboard.instance;
    final modifiers = SelectionModifiers(
      toggle: keyboard.isControlPressed || keyboard.isMetaPressed,
      extend: keyboard.isShiftPressed,
    );
    // Committing first means clicking away from an open editor saves the edit
    // rather than silently discarding what was typed.
    if (_controller.editSession != null && !_controller.isEditing(cell)) {
      _controller.commitEdit();
    }
    _controller.selectCell(cell, modifiers);
    final data = _controller.dataAt(cell.row);
    if (data != null) {
      widget.onCellTap?.call(cell, data);
      final row = _controller.rowAt(cell.row);
      if (row is DataGridRow<T>) widget.onRowTap?.call(row);
    }
  }

  /// Recognises a double tap without a [GestureDetector.onDoubleTap].
  ///
  /// A detector carrying both onTap and onDoubleTap cannot report the single
  /// tap until the double-tap window closes, so every click would select a
  /// row a third of a second late. Tracking the previous tap here keeps
  /// selection immediate - which is also how a spreadsheet behaves - and
  /// leaves no pending timer behind.
  bool _isDoubleTap(CellAddress cell) {
    final now = DateTime.now();
    final previous = _lastTapAt;
    final isRepeat =
        _lastTapCell == cell &&
        previous != null &&
        now.difference(previous) <= kDoubleTapTimeout;
    _lastTapCell = cell;
    _lastTapAt = now;
    return isRepeat;
  }

  void _handleCellDoubleTap(CellAddress cell) {
    final row = _controller.rowAt(cell.row);
    if (row is DataGridRow<T>) widget.onRowDoubleTap?.call(row);
    if (widget.editOnDoubleTap) _controller.beginEdit(cell);
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = _effectiveTheme;
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = _controller.layoutFor(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showHeader) _buildHeader(layout, theme),
              if (widget.showFilterRow) _buildFilterRow(layout, theme),
              Expanded(child: _buildBody(layout, theme)),
              if (widget.showFooter)
                LatticeGridFooter<T>(
                  controller: _controller,
                  theme: theme,
                  pageSizes: widget.pageSizes,
                ),
            ],
          );
        },
      ),
    );
  }

  /// Lays out the three panes, with the middle one scrolling horizontally.
  Widget _buildPanes({
    required GridLayout<T> layout,
    required LatticeGridTheme theme,
    required Widget Function(List<ColumnLayout<T>> columns, bool isFirstPane)
    paneBuilder,
    required Widget Function(List<ColumnLayout<T>> columns, bool isFirstPane)
    scrollingBuilder,
    required ScrollController horizontal,
  }) {
    final hasLeading = layout.leading.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasLeading)
          _FrozenPane(
            width: layout.leadingWidth,
            lineColor: theme.frozenPaneLine,
            lineWidth: theme.gridLineWidth,
            side: ColumnPin.start,
            child: paneBuilder(layout.leading, true),
          ),
        Expanded(
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: layout.scrollingWidth,
              child: scrollingBuilder(layout.scrolling, !hasLeading),
            ),
          ),
        ),
        if (layout.trailing.isNotEmpty)
          _FrozenPane(
            width: layout.trailingWidth,
            lineColor: theme.frozenPaneLine,
            lineWidth: theme.gridLineWidth,
            side: ColumnPin.end,
            child: paneBuilder(layout.trailing, false),
          ),
      ],
    );
  }

  Widget _buildHeader(GridLayout<T> layout, LatticeGridTheme theme) {
    Widget cells(List<ColumnLayout<T>> columns, bool isFirstPane) {
      return Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            LatticeHeaderCell<T>(
              controller: _controller,
              column: columns[i].column,
              width: columns[i].width,
              theme: theme,
              isLastInPane: i == columns.length - 1,
            ),
        ],
      );
    }

    return Container(
      height: theme.headerHeight,
      decoration: BoxDecoration(
        color: theme.headerBackground,
        border: Border(
          bottom: BorderSide(color: theme.gridLine, width: theme.gridLineWidth),
        ),
      ),
      child: _buildPanes(
        layout: layout,
        theme: theme,
        horizontal: _hHeader,
        paneBuilder: cells,
        scrollingBuilder: cells,
      ),
    );
  }

  Widget _buildFilterRow(GridLayout<T> layout, LatticeGridTheme theme) {
    Widget cells(List<ColumnLayout<T>> columns, bool isFirstPane) {
      return Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            LatticeFilterCell<T>(
              // Keyed by field so a column reorder moves the input's state
              // with it instead of leaving text under the wrong column.
              key: ValueKey('filter-${columns[i].column.field}'),
              controller: _controller,
              column: columns[i].column,
              width: columns[i].width,
              theme: theme,
              isLastInPane: i == columns.length - 1,
            ),
        ],
      );
    }

    return Container(
      height: theme.filterRowHeight,
      decoration: BoxDecoration(
        color: theme.headerBackground,
        border: Border(
          bottom: BorderSide(color: theme.gridLine, width: theme.gridLineWidth),
        ),
      ),
      child: _buildPanes(
        layout: layout,
        theme: theme,
        horizontal: _hHeader,
        paneBuilder: cells,
        scrollingBuilder: cells,
      ),
    );
  }

  Widget _buildBody(GridLayout<T> layout, LatticeGridTheme theme) {
    if (_controller.error != null) {
      return widget.errorBuilder?.call(context, _controller.error!) ??
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load rows.\n${_controller.error}',
                textAlign: TextAlign.center,
                style: theme.cellTextStyle.copyWith(color: theme.errorColor),
              ),
            ),
          );
    }
    if (_controller.isLoading && _controller.rowCount == 0) {
      return widget.loadingState ??
          const Center(child: CircularProgressIndicator());
    }
    if (_controller.rowCount == 0) {
      return widget.emptyState ??
          Center(child: Text('No rows', style: theme.footerTextStyle));
    }

    final body = Scrollbar(
      controller: _vScrolling,
      child: _buildPanes(
        layout: layout,
        theme: theme,
        horizontal: _hBody,
        paneBuilder: (columns, isFirstPane) => _buildRows(
          columns: columns,
          isFirstPane: isFirstPane,
          theme: theme,
          scrollController: isFirstPane && layout.leading.isNotEmpty
              ? _vLeading
              : _vTrailing,
          // Only the scrolling pane shows scrollbars and takes wheel input
          // directly; the frozen panes follow it.
          physics: const ClampingScrollPhysics(),
        ),
        scrollingBuilder: (columns, isFirstPane) => _buildRows(
          columns: columns,
          isFirstPane: isFirstPane,
          theme: theme,
          scrollController: _vScrolling,
          physics: const ClampingScrollPhysics(),
        ),
      ),
    );

    if (!widget.stickyGroupHeaders || !_controller.isGrouped) return body;
    return Stack(
      children: [
        body,
        // Rebuilt on scroll on its own, so pinning a header costs one small
        // widget per frame rather than a rebuild of the grid.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: AnimatedBuilder(
            animation: _vScrolling,
            builder: (context, _) => _buildStickyGroupHeader(layout, theme),
          ),
        ),
      ],
    );
  }

  /// The group header for whichever group the first visible row belongs to.
  ///
  /// Only drawn once the real header has scrolled out of view, so it never
  /// doubles the one already on screen.
  Widget _buildStickyGroupHeader(GridLayout<T> layout, LatticeGridTheme theme) {
    if (!_vScrolling.hasClients || widget.rowHeightBuilder != null) {
      return const SizedBox.shrink();
    }
    final offset = _vScrolling.offset;
    if (offset <= 0) return const SizedBox.shrink();

    final first = (offset / _rowHeight).floor();
    GroupGridRow<T>? current;
    for (var i = first; i >= 0; i--) {
      final row = _controller.rowAt(i);
      if (row is GroupGridRow<T>) {
        // A header that is itself still on screen needs no copy.
        if (i == first && offset - i * _rowHeight < 1) {
          return const SizedBox.shrink();
        }
        current = row;
        break;
      }
    }
    if (current == null) return const SizedBox.shrink();

    return Material(
      elevation: 2,
      color: theme.groupRowBackground,
      child: SizedBox(
        height: _rowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (layout.leading.isNotEmpty)
              SizedBox(
                width: layout.leadingWidth,
                child: LatticeGroupRowCells<T>(
                  controller: _controller,
                  row: current,
                  columns: layout.leading,
                  theme: theme,
                  isFirstPane: true,
                ),
              ),
            Expanded(
              child: ClipRect(
                child: LatticeGroupRowCells<T>(
                  controller: _controller,
                  row: current,
                  columns: layout.scrolling,
                  theme: theme,
                  isFirstPane: layout.leading.isEmpty,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRows({
    required List<ColumnLayout<T>> columns,
    required bool isFirstPane,
    required LatticeGridTheme theme,
    required ScrollController scrollController,
    required ScrollPhysics physics,
  }) {
    return ListView.builder(
      controller: scrollController,
      physics: physics,
      // A fixed extent lets the viewport skip straight to the visible range
      // instead of measuring the rows above it.
      itemExtent: widget.rowHeightBuilder == null ? _rowHeight : null,
      itemCount: _controller.rowCount,
      itemBuilder: (context, index) {
        final row = _controller.rowAt(index);
        if (row == null) return const SizedBox.shrink();
        return _buildRow(
          row: row,
          index: index,
          columns: columns,
          isFirstPane: isFirstPane,
          theme: theme,
        );
      },
    );
  }

  Widget _buildRow({
    required GridRow<T> row,
    required int index,
    required List<ColumnLayout<T>> columns,
    required bool isFirstPane,
    required LatticeGridTheme theme,
  }) {
    final height = widget.rowHeightBuilder?.call(row) ?? _rowHeight;

    if (row is GroupGridRow<T>) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: theme.groupRowBackground,
          border: theme.showHorizontalGridLines
              ? Border(
                  bottom: BorderSide(
                    color: theme.gridLine,
                    width: theme.gridLineWidth,
                  ),
                )
              : null,
        ),
        child: LatticeGroupRowCells<T>(
          controller: _controller,
          row: row,
          columns: columns,
          theme: theme,
          isFirstPane: isFirstPane,
        ),
      );
    }

    final dataRow = row as DataGridRow<T>;
    final isSelected = _controller.selection.isRowSelected(index);
    final isHovered = _hoveredRow == index;
    final background = isSelected
        ? theme.selectedRowBackground
        : isHovered
        ? theme.hoveredRowBackground
        : theme.backgroundForRow(index);

    return MouseRegion(
      onEnter: (_) => _setHovered(index),
      onExit: (_) => _setHovered(null),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: background,
          border: theme.showHorizontalGridLines
              ? Border(
                  bottom: BorderSide(
                    color: theme.gridLine,
                    width: theme.gridLineWidth,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            for (var i = 0; i < columns.length; i++)
              _buildCell(
                laid: columns[i],
                row: dataRow,
                index: index,
                theme: theme,
                isLastInPane: i == columns.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell({
    required ColumnLayout<T> laid,
    required DataGridRow<T> row,
    required int index,
    required LatticeGridTheme theme,
    required bool isLastInPane,
  }) {
    final address = CellAddress(index, laid.column.field);
    final rowId = widget.rowId?.call(row.data);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Tap-down rather than tap: see _isDoubleTap.
      onTapDown: (_) {
        _handleCellTap(address);
        if (_isDoubleTap(address)) _handleCellDoubleTap(address);
      },
      child: LatticeCell<T>(
        controller: _controller,
        column: laid.column,
        row: row.data,
        address: address,
        width: laid.width,
        theme: theme,
        cellBuilder: widget.cellBuilder,
        isLastInPane: isLastInPane,
        // Evaluated per visible cell: the rule is a pure function of the
        // value and the column's cached statistics, so this is a handful of
        // comparisons, not a scan.
        decoration: _controller.decorationFor(laid.column.field, row.data),
        highlightChanges: widget.highlightChanges,
        rowId: rowId,
      ),
    );
  }

  void _setHovered(int? index) {
    if (_hoveredRow == index) return;
    setState(() => _hoveredRow = index);
  }
}

/// A pinned pane with a divider on the edge that meets the scrolling pane.
class _FrozenPane extends StatelessWidget {
  const _FrozenPane({
    required this.width,
    required this.child,
    required this.lineColor,
    required this.lineWidth,
    required this.side,
  });

  final double width;
  final Widget child;
  final Color lineColor;
  final double lineWidth;
  final ColumnPin side;

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: lineColor, width: lineWidth);
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: side == ColumnPin.start
              ? Border(right: line)
              : Border(left: line),
        ),
        child: child,
      ),
    );
  }
}
