import 'package:flutter/services.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// The cells of a group header row within one pane.
///
/// The chevron, label and row count are drawn once, in the first pane that
/// exists; the remaining cells show that group's aggregate for their own
/// column, so a subtotal sits under the column it belongs to.
class LatticeGroupRowCells<T> extends StatelessWidget {
  const LatticeGroupRowCells({
    required this.controller,
    required this.row,
    required this.columns,
    required this.theme,
    required this.isFirstPane,
    super.key,
  });

  final GridController<T> controller;
  final GroupGridRow<T> row;
  final List<ColumnLayout<T>> columns;
  final LatticeGridTheme theme;
  final bool isFirstPane;

  /// The aggregate to show under [field], if one was requested for it.
  String? _aggregateText(String field) {
    for (final aggregation in controller.aggregations) {
      if (aggregation.field != field) continue;
      final value = row.aggregates.of(aggregation);
      if (value == null) continue;
      final text = value is double ? value.toStringAsFixed(2) : '$value';
      final label = aggregation.label ?? aggregation.type.name;
      return '$label $text';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < columns.length; i++) {
      final laid = columns[i];
      final isHeaderCell = isFirstPane && i == 0;
      children.add(
        SizedBox(
          width: laid.width,
          child: Padding(
            padding: EdgeInsets.only(
              left: isHeaderCell
                  ? theme.cellPadding.left + row.depth * theme.groupIndent
                  : theme.cellPadding.left,
              right: theme.cellPadding.right,
            ),
            child: Align(
              alignment: isHeaderCell
                  ? Alignment.centerLeft
                  : (laid.column.effectiveAlign == ColumnAlign.end
                        ? Alignment.centerRight
                        : Alignment.centerLeft),
              child: isHeaderCell
                  ? _GroupLabel<T>(
                      controller: controller,
                      row: row,
                      theme: theme,
                    )
                  : Text(
                      _aggregateText(laid.column.field) ?? '',
                      style: theme.footerTextStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ),
      );
    }
    return Row(children: children);
  }
}

class _GroupLabel<T> extends StatelessWidget {
  const _GroupLabel({
    required this.controller,
    required this.row,
    required this.theme,
  });

  final GridController<T> controller;
  final GroupGridRow<T> row;
  final LatticeGridTheme theme;

  @override
  Widget build(BuildContext context) {
    final column = controller.column(row.field);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => controller.toggleGroup(row.path),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A quarter turn rather than two icons, so the chevron animates
            // in place when a group opens.
            AnimatedRotation(
              turns: row.expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 120),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.groupTextStyle.color,
              ),
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                '${column?.title ?? row.field}: ${row.label}',
                style: theme.groupTextStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text('(${row.rowCount})', style: theme.footerTextStyle),
          ],
        ),
      ),
    );
  }
}
