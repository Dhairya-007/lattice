import 'package:flutter/material.dart';
import 'package:lattice_core/lattice_core.dart';

import 'theme.dart';

/// Footer bar: row counts, grid-wide aggregates and page controls.
class LatticeGridFooter<T> extends StatelessWidget {
  const LatticeGridFooter({
    required this.controller,
    required this.theme,
    this.pageSizes = const [25, 50, 100, 250],
    super.key,
  });

  final GridController<T> controller;
  final LatticeGridTheme theme;

  /// Page sizes offered in the footer menu.
  final List<int> pageSizes;

  String get _countLabel {
    final matched = controller.matchedCount;
    final total = controller.totalCount;
    if (matched == total) return '$total ${total == 1 ? 'row' : 'rows'}';
    return '$matched of $total rows';
  }

  String? get _aggregateLabel {
    if (controller.aggregations.isEmpty) return null;
    final parts = <String>[];
    for (final aggregation in controller.aggregations) {
      final value = controller.aggregates.of(aggregation);
      if (value == null) continue;
      final text = value is double ? value.toStringAsFixed(2) : '$value';
      final column = controller.column(aggregation.field);
      parts.add(
        '${aggregation.label ?? '${column?.title ?? aggregation.field} '
            '${aggregation.type.name}'}: $text',
      );
    }
    return parts.isEmpty ? null : parts.join('   ');
  }

  @override
  Widget build(BuildContext context) {
    final aggregates = _aggregateLabel;
    final paged = controller.pageSize != null;
    return Container(
      height: theme.footerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.footerBackground,
        border: Border(
          top: BorderSide(color: theme.gridLine, width: theme.gridLineWidth),
        ),
      ),
      child: Row(
        children: [
          Text(_countLabel, style: theme.footerTextStyle),
          if (controller.selection.rowCount > 0) ...[
            Text('   ·   ', style: theme.footerTextStyle),
            Text(
              '${controller.selection.rowCount} selected',
              style: theme.footerTextStyle,
            ),
          ],
          if (aggregates != null) ...[
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                aggregates,
                style: theme.footerTextStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          if (paged) ...[
            DropdownButton<int>(
              value: controller.pageSize,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: theme.footerTextStyle,
              items: [
                for (final size in pageSizes)
                  DropdownMenuItem<int>(value: size, child: Text('$size / page')),
              ],
              onChanged: (size) {
                if (size != null) controller.setPageSize(size);
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.first_page, size: 18),
              tooltip: 'First page',
              onPressed:
                  controller.hasPreviousPage ? () => controller.goToPage(0) : null,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 18),
              tooltip: 'Previous page',
              onPressed: controller.hasPreviousPage ? controller.previousPage : null,
            ),
            Text(
              'Page ${controller.pageIndex + 1} of ${controller.pageCount}',
              style: theme.footerTextStyle,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 18),
              tooltip: 'Next page',
              onPressed: controller.hasNextPage ? controller.nextPage : null,
            ),
            IconButton(
              icon: const Icon(Icons.last_page, size: 18),
              tooltip: 'Last page',
              onPressed: controller.hasNextPage
                  ? () => controller.goToPage(controller.pageCount - 1)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}
