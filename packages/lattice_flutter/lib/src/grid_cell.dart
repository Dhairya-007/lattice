import 'package:flutter/semantics.dart';
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
    this.decoration = CellDecoration.none,
    this.highlightChanges = false,
    this.rowId,
    this.leading,
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

  /// Conditional formatting for this cell, from the column's [CellRule].
  final CellDecoration decoration;

  /// Whether to flash when this cell's value changes under a live feed.
  final bool highlightChanges;

  /// Identity of the row, so a flash can tell an updated value from a row
  /// that merely moved into this position.
  final Object? rowId;

  /// Drawn before the value, inside the cell's padding.
  ///
  /// How a tree's indentation and its disclosure control reach the first
  /// column without taking width away from the cell or from the value.
  final Widget? leading;

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

    final text = column.formattedValue(row);

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
        text,
        style: decoration.isEmpty
            ? theme.cellTextStyle
            : theme.cellTextStyle.copyWith(
                color: decoration.tone == CellTone.neutral
                    ? null
                    : theme.toneColor(decoration.tone),
                fontWeight: decoration.bold ? FontWeight.w600 : null,
              ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: _textAlignFor(column.effectiveAlign),
      );
    }

    if (highlightChanges && rowId != null && !isEditing) {
      content = _ChangeFlash(
        rowId: rowId!,
        value: text,
        color: theme.changeFlashColor,
        duration: theme.changeFlashDuration,
        child: content,
      );
    }

    final indent = leading;
    if (indent != null) {
      content = Row(
        children: [
          indent,
          Flexible(child: content),
        ],
      );
    }

    final tint = isEditing ? null : theme.backgroundFor(decoration);
    final bar = isEditing ? null : decoration.bar;

    // What a screen reader says for this cell. Without the column title a
    // value is meaningless out of context, and without the row number the
    // listener cannot tell which record they are on.
    final semanticLabel =
        'Row ${address.row + 1}, ${column.title}'
        '${isSelected ? ', selected' : ''}';

    return Semantics(
      label: semanticLabel,
      value: text,
      selected: isSelected,
      focused: isActive,
      textField: isEditing,
      readOnly: !column.editable,
      // Traversal follows the columns rather than the widget tree, which
      // frozen panes would otherwise scramble.
      sortKey: OrdinalSortKey(address.row * 1000 + width),
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected && !isEditing
                ? theme.selectedCellBackground
                : tint,
            border: Border(
              right: theme.showVerticalGridLines && !isLastInPane
                  ? BorderSide(
                      color: theme.gridLine,
                      width: theme.gridLineWidth,
                    )
                  : BorderSide.none,
            ),
          ),
          child: Container(
            foregroundDecoration: isActive && !isEditing
                ? BoxDecoration(
                    border: Border.all(
                      color: theme.focusedCellBorder,
                      width: 2,
                    ),
                  )
                : null,
            padding: theme.cellPadding,
            alignment: _alignmentFor(column.effectiveAlign),
            // The bar sits behind the text rather than beside it, so adding
            // one never costs the value any room.
            // The bar is decoration for the value beside it; announcing it
            // would just be noise.
            child: bar == null
                ? content
                : Stack(
                    fit: StackFit.passthrough,
                    children: [
                      Positioned.fill(
                        child: ExcludeSemantics(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: bar,
                              heightFactor: 0.62,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: theme
                                      .toneColor(decoration.tone)
                                      .withValues(alpha: theme.dataBarOpacity),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: _alignmentFor(column.effectiveAlign),
                        child: content,
                      ),
                    ],
                  ),
          ),
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
      // Merged, so the field is one node: the TextField makes a node of its
      // own, and without the merge it is that node a screen reader reaches,
      // not the label, value and live region set here.
      child: MergeSemantics(
        child: Semantics(
          label: '${widget.column.title} editor',
          textField: true,
          // A live region is announced when its value changes, which covers
          // the error appearing without reaching for SemanticsService - whose
          // announce is deprecated for being single-window.
          liveRegion: error != null,
          value: error ?? _text.text,
          child: Tooltip(
            message: error ?? '',
            // An empty message renders nothing, so a valid edit shows no tooltip.
            child: TextField(
              controller: _text,
              focusNode: _focus,
              style: theme.cellTextStyle,
              textAlign: LatticeCell._textAlignFor(
                widget.column.effectiveAlign,
              ),
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
        ),
      ),
    );
  }
}

/// Briefly tints its child when the value changes under the same row.
///
/// Live grids - logs, prices, telemetry - are much easier to read when a
/// change announces itself. The flash is keyed on [rowId] as well as the
/// value so that a row scrolling or sorting into this position does not look
/// like an update: only a genuine change to the same row flashes.
class _ChangeFlash extends StatefulWidget {
  const _ChangeFlash({
    required this.rowId,
    required this.value,
    required this.duration,
    required this.child,
    this.color,
  });

  final Object rowId;
  final String value;
  final Color? color;
  final Duration duration;
  final Widget child;

  @override
  State<_ChangeFlash> createState() => _ChangeFlashState();
}

class _ChangeFlashState extends State<_ChangeFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didUpdateWidget(_ChangeFlash old) {
    super.didUpdateWidget(old);
    if (old.rowId == widget.rowId && old.value != widget.value) {
      _controller.forward(from: 0);
    } else if (old.rowId != widget.rowId) {
      // A different row took this slot: cancel rather than flash.
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    if (color == null) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.value == 0 || _controller.isCompleted) return child!;
        // Fade out rather than in: the change should be loudest the moment
        // it happens.
        final strength = 1 - _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.38 * strength),
            borderRadius: BorderRadius.circular(3),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
