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
    super.key,
  });

  final GridController<T> controller;
  final GridColumn<T> column;
  final double width;
  final LatticeGridTheme theme;
  final bool isLastInPane;

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

    final label = Text(
      column.title,
      style: theme.headerTextStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final children = <Widget>[
      if (column.effectiveAlign == ColumnAlign.end)
        const Spacer()
      else
        Flexible(child: label),
      if (column.effectiveAlign == ColumnAlign.end) Flexible(child: label),
      if (sort != null) ...[
        const SizedBox(width: 4),
        Icon(
          sort.isAscending ? Icons.arrow_upward : Icons.arrow_downward,
          size: 14,
          color: theme.headerForeground,
        ),
        if (showPriority)
          Text(
            '$priority',
            style: theme.headerTextStyle.copyWith(fontSize: 10),
          ),
      ],
    ];

    Widget content = Container(
      padding: theme.cellPadding,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.max, children: children),
    );

    if (column.sortable) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: content),
      );
    }

    if (column.tooltip != null) {
      content = Tooltip(message: column.tooltip!, child: content);
    }

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: theme.showVerticalGridLines && !isLastInPane
                ? BorderSide(color: theme.gridLine, width: theme.gridLineWidth)
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
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Invisible drag target straddling a header's trailing edge.
class _ResizeHandle<T> extends StatefulWidget {
  const _ResizeHandle({
    required this.controller,
    required this.column,
    required this.startWidth,
  });

  final GridController<T> controller;
  final GridColumn<T> column;
  final double startWidth;

  @override
  State<_ResizeHandle<T>> createState() => _ResizeHandleState<T>();
}

class _ResizeHandleState<T> extends State<_ResizeHandle<T>> {
  double _width = 0;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Accumulate from the width at drag start rather than reading it back
        // each frame: the controller clamps, so feeding the clamped value back
        // in would make the drag stick at the minimum.
        onHorizontalDragStart: (_) => _width = widget.startWidth,
        onHorizontalDragUpdate: (details) {
          _width += details.delta.dx;
          widget.controller.resizeColumn(widget.column.field, _width);
        },
        onDoubleTap: () =>
            widget.controller.resetColumnWidth(widget.column.field),
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
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
    super.key,
  });

  final HeaderRow row;
  final List<ColumnLayout<T>> columns;
  final LatticeGridTheme theme;
  final double height;

  @override
  Widget build(BuildContext context) {
    final segments = layoutHeaderRow<T>(columns, row);
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
