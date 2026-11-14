/// The outcome of pasting clipboard text into a cell range.
library;

import 'selection.dart';

/// Why one cell of a paste could not be written.
class PasteRejection {
  const PasteRejection({
    required this.cell,
    required this.text,
    required this.reason,
  });

  /// Where it would have gone.
  final CellAddress cell;

  /// The clipboard text that was rejected, so a message can quote it.
  final String text;

  /// What was wrong with it, in the words of the column's validator where
  /// there was one.
  final String reason;

  @override
  String toString() => 'PasteRejection(${cell.field} row ${cell.row}: $reason)';
}

/// What a paste did, or would have done.
class PasteResult {
  const PasteResult({
    this.rowsChanged = 0,
    this.cellsChanged = 0,
    this.cellsClipped = 0,
    this.rejections = const [],
    this.applied = false,
  });

  /// Nothing was pasted, because there was nowhere to paste it.
  const PasteResult.noTarget()
      : rowsChanged = 0,
        cellsChanged = 0,
        cellsClipped = 0,
        rejections = const [],
        applied = false;

  final int rowsChanged;
  final int cellsChanged;

  /// Cells the clipboard carried that fell outside the grid.
  ///
  /// Pasting a 10-row block into the last 3 rows clips the other 7 rather
  /// than creating rows: the grid does not know how to make a row, and a
  /// source that does should be given the data itself.
  final int cellsClipped;

  /// Cells that could not be written, each with its reason.
  final List<PasteRejection> rejections;

  /// Whether anything was actually written.
  final bool applied;

  bool get hasRejections => rejections.isNotEmpty;

  bool get isEmpty => cellsChanged == 0 && rejections.isEmpty;

  @override
  String toString() => 'PasteResult($cellsChanged cells in $rowsChanged rows, '
      '${rejections.length} rejected, applied: $applied)';
}
