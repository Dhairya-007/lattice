import 'package:flutter/services.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// One header cell: title, sort indicator and resize handle.
class LatticeHeaderCell<T> extends StatelessWidget {
  const LatticeHeaderCell({
    required this.controller,
    required this.column,
    required this.width,
    required this.theme,
    this.isLastInPane = false,
    this.showMenu = false,
    this.allowReorder = false,
    super.key,
  });

  final GridController<T> controller;
  final GridColumn<T> column;
  final double width;
  final LatticeGridTheme theme;
  final bool isLastInPane;

  /// Shows the per-column menu: sort, pin, hide, reset width.
  final bool showMenu;

  /// Allows dragging this header onto another to reorder the columns.
  final bool allowReorder;

  void _onTap() {
    // Ctrl (or cmd on Apple platforms) builds a multi-level sort instead of
    // replacing it, which is the convention users arrive with.
    final keyboard = HardwareKeyboard.instance;
    controller.toggleSort(
      column.field,
      additive: keyboard.isControlPressed || keyboard.isMetaPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sort = controller.sortFor(column.field);
    final priority = controller.sortPriority(column.field);
    final showPriority = priority != null && controller.sorts.length > 1;

    // The title and the level badge are both spoken by the Semantics
    // wrapper below, so neither is left in the tree: a Text owns the
    // nearest node, and the header's own label and flags would never reach
    // a screen reader.
    final label = ExcludeSemantics(
      child: Text(
        column.title,
        style: theme.headerTextStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final children = <Widget>[
      if (column.effectiveAlign == ColumnAlign.end)
        const Spacer()
      else
        Flexible(child: label),
      if (column.effectiveAlign == ColumnAlign.end) Flexible(child: label),
      if (sort != null) ...[
        const SizedBox(width: 4),
        // Half a turn rather than two icons, so reversing a sort reads as
        // the same arrow turning over.
        AnimatedRotation(
          turns: sort.isAscending ? 0 : 0.5,
          duration: theme.animations
              ? theme.animationDuration * 1.6
              : Duration.zero,
          curve: Curves.easeOutBack,
          child: Icon(
            Icons.arrow_upward,
            size: 14,
            color: theme.focusedCellBorder,
          ),
        ),
        if (showPriority)
          Container(
            margin: const EdgeInsets.only(left: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: theme.focusedCellBorder.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: ExcludeSemantics(
              child: Text(
                '$priority',
                style: theme.headerTextStyle.copyWith(
                  fontSize: 9,
                  height: 1,
                  color: theme.focusedCellBorder,
                ),
              ),
            ),
          ),
      ],
    ];

    Widget content = Container(
      padding: theme.cellPadding,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          ...children,
          // The slot is reserved whether or not the menu is shown, so the
          // title does not shift when the pointer enters the cell.
          if (showMenu) _ColumnMenu<T>(controller: controller, column: column),
        ],
      ),
    );

    if (column.sortable) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The wrapper below carries the tap: left to annotate itself, the
        // detector would put a bare node between the header's node and the
        // title, and that is the node a screen reader would land on.
        excludeFromSemantics: true,
        onTap: _onTap,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: content),
      );
    }

    if (column.tooltip != null) {
      content = Tooltip(message: column.tooltip!, child: content);
    }

    if (allowReorder) {
      // Captured before the wrapping below: a closure captures the variable,
      // not its value, so a builder that read `content` would read the
      // wrapper it is inside and recurse forever.
      final inner = content;
      // The payload is the field, so a drop only needs to know where it
      // landed; the controller works out the new order.
      content = DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != column.field,
        onAcceptWithDetails: (details) =>
            _acceptDrop(details.data, controller, column),
        builder: (context, candidate, _) {
          final target = candidate.isNotEmpty;
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: target
                      ? theme.focusedCellBorder
                      : const Color(0x00000000),
                  width: 2,
                ),
              ),
            ),
            child: inner,
          );
        },
      );
      final draggableChild = content;
      content = Draggable<String>(
        data: column.field,
        axis: Axis.horizontal,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _DragGhost(title: column.title, theme: theme),
        childWhenDragging: Opacity(opacity: 0.35, child: draggableChild),
        child: draggableChild,
      );
    }

    // The sort state has to be spoken, not just drawn: an arrow is invisible
    // to a screen reader, and the sort level matters once there are several.
    final sortSpoken = sort == null
        ? ''
        : ', sorted ${sort.isAscending ? 'ascending' : 'descending'}'
              '${showPriority ? ', sort level $priority' : ''}';

    return Semantics(
      header: true,
      button: column.sortable,
      label: '${column.title}$sortSpoken',
      hint: column.sortable ? 'Activate to change the sort' : null,
      onTap: column.sortable ? _onTap : null,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              right: theme.showVerticalGridLines && !isLastInPane
                  ? BorderSide(
                      color: theme.gridLine,
                      width: theme.gridLineWidth,
                    )
                  : BorderSide.none,
            ),
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              content,
              if (column.resizable)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: -theme.resizeHandleWidth / 2,
                  width: theme.resizeHandleWidth,
                  child: _ResizeHandle<T>(
                    controller: controller,
                    column: column,
                    startWidth: width,
                    theme: theme,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Moves [field] to where [onto] currently sits.
///
/// Dropping onto a column in a different pane moves it into that pane as
/// well, which is how a column is dragged out of - or into - a frozen one.
void _acceptDrop<T>(
  String field,
  GridController<T> controller,
  GridColumn<T> onto,
) {
  final target = controller.visibleColumns.indexWhere(
    (c) => c.field == onto.field,
  );
  if (target < 0) return;
  final moved = controller.column(field);
  if (moved != null && moved.pin != onto.pin) {
    controller.setColumnPin(field, onto.pin);
  }
  controller.moveColumn(field, target);
}

/// The ghost that follows the pointer while a header is being dragged.
class _DragGhost extends StatelessWidget {
  const _DragGhost({required this.title, required this.theme});

  final String title;
  final LatticeGridTheme theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x00000000),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.headerBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.focusedCellBorder, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 12),
          ],
        ),
        child: Text(title, style: theme.headerTextStyle),
      ),
    );
  }
}

/// What one header's menu offers.
enum _ColumnAction {
  sortAsc,
  sortDesc,
  clearSort,
  pinStart,
  pinEnd,
  unpin,
  hide,
  resetWidth,
  manage,
}

/// The per-column menu.
class _ColumnMenu<T> extends StatelessWidget {
  const _ColumnMenu({required this.controller, required this.column});

  final GridController<T> controller;
  final GridColumn<T> column;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      child: PopupMenuButton<_ColumnAction>(
        tooltip: 'Column options',
        padding: EdgeInsets.zero,
        iconSize: 15,
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (action) => _apply(context, action),
        itemBuilder: (context) => [
          if (column.sortable) ...[
            const PopupMenuItem(
              value: _ColumnAction.sortAsc,
              child: _MenuRow(
                icon: Icons.arrow_upward,
                label: 'Sort ascending',
              ),
            ),
            const PopupMenuItem(
              value: _ColumnAction.sortDesc,
              child: _MenuRow(
                icon: Icons.arrow_downward,
                label: 'Sort descending',
              ),
            ),
            if (controller.sortFor(column.field) != null)
              const PopupMenuItem(
                value: _ColumnAction.clearSort,
                child: _MenuRow(icon: Icons.clear, label: 'Clear sort'),
              ),
            const PopupMenuDivider(),
          ],
          if (column.pin != ColumnPin.start)
            const PopupMenuItem(
              value: _ColumnAction.pinStart,
              child: _MenuRow(
                icon: Icons.push_pin_outlined,
                label: 'Pin to the start',
              ),
            ),
          if (column.pin != ColumnPin.end)
            const PopupMenuItem(
              value: _ColumnAction.pinEnd,
              child: _MenuRow(
                icon: Icons.push_pin_outlined,
                label: 'Pin to the end',
              ),
            ),
          if (column.pin != ColumnPin.none)
            const PopupMenuItem(
              value: _ColumnAction.unpin,
              child: _MenuRow(icon: Icons.push_pin, label: 'Unpin'),
            ),
          const PopupMenuDivider(),
          if (column.resizable)
            const PopupMenuItem(
              value: _ColumnAction.resetWidth,
              child: _MenuRow(icon: Icons.width_normal, label: 'Reset width'),
            ),
          const PopupMenuItem(
            value: _ColumnAction.hide,
            child: _MenuRow(icon: Icons.visibility_off, label: 'Hide column'),
          ),
          const PopupMenuItem(
            value: _ColumnAction.manage,
            child: _MenuRow(icon: Icons.view_column, label: 'Choose columns…'),
          ),
        ],
      ),
    );
  }

  void _apply(BuildContext context, _ColumnAction action) {
    switch (action) {
      case _ColumnAction.sortAsc:
        controller.setSorts([SortSpec(column.field)]);
      case _ColumnAction.sortDesc:
        controller.setSorts([
          SortSpec(column.field, direction: SortDirection.descending),
        ]);
      case _ColumnAction.clearSort:
        controller.clearSorts();
      case _ColumnAction.pinStart:
        controller.setColumnPin(column.field, ColumnPin.start);
      case _ColumnAction.pinEnd:
        controller.setColumnPin(column.field, ColumnPin.end);
      case _ColumnAction.unpin:
        controller.setColumnPin(column.field, ColumnPin.none);
      case _ColumnAction.resetWidth:
        controller.resetColumnWidth(column.field);
      case _ColumnAction.hide:
        controller.setColumnVisible(column.field, false);
      case _ColumnAction.manage:
        showColumnChooser<T>(context, controller);
    }
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 16), const SizedBox(width: 10), Text(label)],
    );
  }
}

/// Opens a dialog listing every column, with a switch per column.
///
/// The per-column menu can hide a column; without this there would be no way
/// to bring one back, which is the usual way a column chooser is forgotten.
Future<void> showColumnChooser<T>(
  BuildContext context,
  GridController<T> controller,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Columns'),
      content: SizedBox(
        width: 320,
        child: _ColumnChooserList<T>(controller: controller),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

/// The list inside the chooser.
///
/// Stateful so it subscribes to the controller exactly once. Built inline it
/// would add a listener on every rebuild, and since each listener triggers
/// another rebuild, the subscriptions would multiply with every change.
class _ColumnChooserList<T> extends StatefulWidget {
  const _ColumnChooserList({required this.controller});

  final GridController<T> controller;

  @override
  State<_ColumnChooserList<T>> createState() => _ColumnChooserListState<T>();
}

class _ColumnChooserListState<T> extends State<_ColumnChooserList<T>> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListView(
      shrinkWrap: true,
      children: [
        for (final column in controller.columns)
          SwitchListTile(
            dense: true,
            title: Text(column.title),
            value: column.visible,
            // The last visible column cannot be hidden: an empty grid has no
            // header left to bring anything back from.
            onChanged: column.visible && controller.visibleColumns.length <= 1
                ? null
                : (on) => controller.setColumnVisible(column.field, on),
          ),
      ],
    );
  }
}

/// Invisible drag target straddling a header's trailing edge.
class _ResizeHandle<T> extends StatefulWidget {
  const _ResizeHandle({
    required this.controller,
    required this.column,
    required this.startWidth,
    required this.theme,
  });

  final GridController<T> controller;
  final GridColumn<T> column;
  final double startWidth;
  final LatticeGridTheme theme;

  @override
  State<_ResizeHandle<T>> createState() => _ResizeHandleState<T>();
}

class _ResizeHandleState<T> extends State<_ResizeHandle<T>> {
  double _width = 0;
  bool _dragging = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final active = _dragging || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Accumulate from the width at drag start rather than reading it back
        // each frame: the controller clamps, so feeding the clamped value back
        // in would make the drag stick at the minimum.
        onHorizontalDragStart: (_) {
          _width = widget.startWidth;
          setState(() => _dragging = true);
        },
        onHorizontalDragUpdate: (details) {
          _width += details.delta.dx;
          widget.controller.resizeColumn(widget.column.field, _width);
        },
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onDoubleTap: () =>
            widget.controller.resetColumnWidth(widget.column.field),
        // A grip that shows up under the cursor, so the drag target is
        // discoverable instead of being an invisible strip you find by luck.
        child: Center(
          child: AnimatedContainer(
            duration: theme.animations
                ? theme.animationDuration
                : Duration.zero,
            width: active ? 2 : 0,
            decoration: BoxDecoration(
              color: theme.focusedCellBorder,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of per-column filter inputs under the header.
class LatticeFilterCell<T> extends StatefulWidget {
  const LatticeFilterCell({
    required this.controller,
    required this.column,
    required this.width,
    required this.theme,
    this.isLastInPane = false,
    super.key,
  });

  final GridController<T> controller;
  final GridColumn<T> column;
  final double width;
  final LatticeGridTheme theme;
  final bool isLastInPane;

  @override
  State<LatticeFilterCell<T>> createState() => _LatticeFilterCellState<T>();
}

class _LatticeFilterCellState<T> extends State<LatticeFilterCell<T>> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    final existing = widget.controller.columnFilters[widget.column.field];
    _text = TextEditingController(
      text: existing?.value == null ? '' : '${existing!.value}',
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Picks a sensible operator for the column's type.
  ///
  /// Text reads as a substring search, which is what a filter row implies;
  /// numbers, dates and booleans compare for equality, since a substring of a
  /// number is not a question anyone is asking.
  void _apply(String raw) {
    final field = widget.column.field;
    if (raw.trim().isEmpty) {
      widget.controller.setColumnFilter(field, null);
      return;
    }
    switch (widget.column.type) {
      case ColumnType.text:
      case ColumnType.custom:
        widget.controller.setColumnFilter(
          field,
          FilterCondition(
            field: field,
            operator: FilterOperator.contains,
            value: raw,
          ),
        );
      case ColumnType.number:
      case ColumnType.date:
      case ColumnType.boolean:
        final parsed = coerceValue(raw, widget.column.type);
        // An unparseable number would match nothing and look like a bug, so
        // the filter is simply not applied until the text parses.
        widget.controller.setColumnFilter(
          field,
          parsed == null
              ? null
              : FilterCondition(
                  field: field,
                  operator: FilterOperator.equals,
                  value: parsed,
                ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return SizedBox(
      width: widget.width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: theme.showVerticalGridLines && !widget.isLastInPane
                ? BorderSide(color: theme.gridLine, width: theme.gridLineWidth)
                : BorderSide.none,
          ),
        ),
        child: widget.column.filterable
            ? Semantics(
                label: 'Filter ${widget.column.title}',
                textField: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: TextField(
                    controller: _text,
                    style: theme.cellTextStyle,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filter',
                      hintStyle: theme.footerTextStyle,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      border: const OutlineInputBorder(),
                      suffixIcon: _text.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              onPressed: () {
                                _text.clear();
                                _apply('');
                              },
                            ),
                    ),
                    onChanged: (value) {
                      _apply(value);
                      setState(() {}); // refresh the clear button
                    },
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// One row of a stacked header, drawn above the column titles.
///
/// Each band is drawn over whichever columns it currently covers, so a
/// reorder, a hidden column or a frozen pane boundary changes the geometry
/// without the band definition knowing anything about it.
class LatticeStackedHeaderRow<T> extends StatelessWidget {
  const LatticeStackedHeaderRow({
    required this.row,
    required this.columns,
    required this.theme,
    required this.height,
    this.drawnBands,
    super.key,
  });

  final HeaderRow row;
  final List<ColumnLayout<T>> columns;
  final LatticeGridTheme theme;
  final double height;

  /// Shared across the panes of one header row, so a band split by a frozen
  /// pane is titled in the first pane only.
  final Set<HeaderBand>? drawnBands;

  @override
  Widget build(BuildContext context) {
    final segments = layoutHeaderRow<T>(columns, row, drawn: drawnBands);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final segment in segments)
            SizedBox(
              width: segment.width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    right: theme.showVerticalGridLines
                        ? BorderSide(
                            color: theme.gridLine,
                            width: theme.gridLineWidth,
                          )
                        : BorderSide.none,
                  ),
                ),
                child: segment.isGap || segment.isContinuation
                    // A band split across panes repeats its geometry but not
                    // its title, so the header does not read as two things.
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: theme.cellPadding,
                        child: Align(
                          alignment: _alignmentFor(segment.band!.align),
                          child: Tooltip(
                            message: segment.band!.tooltip ?? '',
                            child: Text(
                              segment.band!.title,
                              style: theme.headerTextStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  static Alignment _alignmentFor(ColumnAlign align) {
    switch (align) {
      case ColumnAlign.start:
        return Alignment.centerLeft;
      case ColumnAlign.center:
        return Alignment.center;
      case ColumnAlign.end:
        return Alignment.centerRight;
    }
  }
}
