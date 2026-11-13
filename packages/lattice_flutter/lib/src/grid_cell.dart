import 'package:flutter/services.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Builds the contents of a cell, replacing the default text.
///
/// Takes the build context, the column being drawn and the row it is drawn
/// from. Written on one line on purpose: formatter versions disagree about
/// where to break a multi-line function type.
typedef GridCellBuilder<T> = Widget Function(BuildContext, GridColumn<T>, T);

/// One data cell.
///
/// Draws the value, the selection and focus states, and swaps in an editor
/// while this cell is the one being edited.
class LatticeCell<T> extends StatelessWidget {
  const LatticeCell({
    required this.controller,
    required this.column,
    required this.row,
    required this.address,
    required this.width,
    required this.theme,
    this.cellBuilder,
    this.isLastInPane = false,
    super.key,
  });

  final GridController<T> controller;
  final GridColumn<T> column;
  final T row;
  final CellAddress address;
  final double width;
  final LatticeGridTheme theme;
  final GridCellBuilder<T>? cellBuilder;

  /// Suppresses the trailing grid line at the edge of a pane, where the pane
  /// divider already draws one.
  final bool isLastInPane;

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

  static TextAlign _textAlignFor(ColumnAlign align) {
    switch (align) {
      case ColumnAlign.start:
        return TextAlign.start;
      case ColumnAlign.center:
        return TextAlign.center;
      case ColumnAlign.end:
        return TextAlign.end;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = controller.isEditing(address);
    final isActive = controller.selection.activeCell == address;
    final isSelected = controller.selection.isCellSelected(address);

    Widget content;
    if (isEditing) {
      content = _CellEditor<T>(
        controller: controller,
        column: column,
        theme: theme,
      );
    } else if (cellBuilder != null) {
      content = cellBuilder!(context, column, row);
    } else {
      content = Text(
        column.formattedValue(row),
        style: theme.cellTextStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: _textAlignFor(column.effectiveAlign),
      );
    }

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected && !isEditing ? theme.selectedCellBackground : null,
          border: Border(
            right: theme.showVerticalGridLines && !isLastInPane
                ? BorderSide(color: theme.gridLine, width: theme.gridLineWidth)
                : BorderSide.none,
          ),
        ),
        child: Container(
          foregroundDecoration: isActive && !isEditing
              ? BoxDecoration(
                  border: Border.all(color: theme.focusedCellBorder, width: 2),
                )
              : null,
          padding: theme.cellPadding,
          alignment: _alignmentFor(column.effectiveAlign),
          child: content,
        ),
      ),
    );
  }
}

/// The text editor shown while a cell is being edited.
///
/// Lives in its own stateful widget so the [TextEditingController] and focus
/// are created once per edit session rather than on every grid rebuild, which
/// is what keeps the caret from jumping while typing.
class _CellEditor<T> extends StatefulWidget {
  const _CellEditor({
    required this.controller,
    required this.column,
    required this.theme,
  });

  final GridController<T> controller;
  final GridColumn<T> column;
  final LatticeGridTheme theme;

  @override
  State<_CellEditor<T>> createState() => _CellEditorState<T>();
}

class _CellEditorState<T> extends State<_CellEditor<T>> {
  late final TextEditingController _text;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    final session = widget.controller.editSession;
    final initial = session?.value;
    _text = TextEditingController(text: initial == null ? '' : '$initial')
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: initial == null ? 0 : '$initial'.length,
      );
    _focus = FocusNode();
    // Request focus after the first frame: the editor is built during the
    // rebuild that opened the session, when the node is not yet attached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    widget.controller.updateEdit(coerceValue(_text.text, widget.column.type));
    widget.controller.commitEdit();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.controller.cancelEdit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _commit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.controller.editSession?.error;
    final theme = widget.theme;
    return Focus(
      onKeyEvent: _onKey,
      child: Tooltip(
        message: error ?? '',
        // An empty message renders nothing, so a valid edit shows no tooltip.
        child: TextField(
          controller: _text,
          focusNode: _focus,
          style: theme.cellTextStyle,
          textAlign: LatticeCell._textAlignFor(widget.column.effectiveAlign),
          keyboardType: widget.column.type == ColumnType.number
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : TextInputType.text,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 8,
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: error == null
                    ? theme.focusedCellBorder
                    : theme.errorColor,
                width: 2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: error == null
                    ? theme.focusedCellBorder
                    : theme.errorColor,
                width: 2,
              ),
            ),
          ),
          onChanged: (text) => widget.controller.updateEdit(
            coerceValue(text, widget.column.type),
          ),
          onSubmitted: (_) => _commit(),
        ),
      ),
    );
  }
}
