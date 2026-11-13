/// Header rows that span several columns.
///
/// A wide grid usually has columns that belong together — four quarters of a
/// year, a street/city/postcode address, a set of metrics for one service.
/// A stacked header says so once, above them, instead of repeating the
/// grouping in every column title.
library;

import 'column.dart';
import 'layout.dart';

/// One cell of a stacked header row, spanning the columns it names.
class HeaderBand {
  const HeaderBand({
    required this.title,
    required this.fields,
    this.align = ColumnAlign.center,
    this.tooltip,
  });

  /// Text shown across the span.
  final String title;

  /// Fields this band covers, by [GridColumn.field].
  ///
  /// Order does not matter: the band is drawn over wherever those columns
  /// actually are, which is what keeps it correct after a reorder.
  final List<String> fields;

  final ColumnAlign align;

  final String? tooltip;

  @override
  String toString() => 'HeaderBand($title over ${fields.join(', ')})';
}

/// One row of a stacked header, drawn above the column titles.
///
/// Rows are listed outermost first, so `[regions, quarters]` draws regions
/// along the top and quarters beneath them.
class HeaderRow {
  const HeaderRow(this.bands);

  final List<HeaderBand> bands;

  /// Every field covered by this row.
  Set<String> get fields => {for (final band in bands) ...band.fields};

  @override
  String toString() => 'HeaderRow(${bands.length} bands)';
}

/// A band resolved against a laid-out pane: where to draw it, and how wide.
class HeaderBandLayout<T> {
  const HeaderBandLayout({
    required this.band,
    required this.offset,
    required this.width,
    required this.columns,
    required this.isContinuation,
  });

  /// The band this segment belongs to, or null for the gap between bands.
  final HeaderBand? band;

  /// Left edge within the pane.
  final double offset;

  final double width;

  /// The columns this segment covers, in display order.
  final List<ColumnLayout<T>> columns;

  /// Whether an earlier segment of the same band was already drawn.
  ///
  /// A band whose columns are split — by a frozen pane boundary, or by the
  /// user moving an unrelated column into the middle of it — is drawn as
  /// several segments. Only the first repeats the title, so the header does
  /// not read as two separate things with the same name.
  final bool isContinuation;

  /// Whether this segment is a gap: columns no band covers.
  bool get isGap => band == null;

  double get end => offset + width;

  @override
  String toString() =>
      'HeaderBandLayout(${band?.title ?? 'gap'}, $width @ $offset)';
}

/// Resolves [row] against one pane's laid-out columns.
///
/// Walks the pane in display order and starts a new segment whenever the
/// covering band changes, which handles three awkward cases without special
/// casing any of them: a band split across panes, a band interrupted by a
/// column the user moved into it, and columns no band covers.
List<HeaderBandLayout<T>> layoutHeaderRow<T>(
  List<ColumnLayout<T>> pane,
  HeaderRow row,
) {
  if (pane.isEmpty) return const [];

  final owner = <String, HeaderBand>{};
  for (final band in row.bands) {
    for (final field in band.fields) {
      // First band wins, so overlapping bands cannot double-cover a column.
      owner.putIfAbsent(field, () => band);
    }
  }

  final segments = <HeaderBandLayout<T>>[];
  final drawn = <HeaderBand>{};

  HeaderBand? currentBand;
  var currentColumns = <ColumnLayout<T>>[];
  var currentOffset = 0.0;
  var currentWidth = 0.0;
  var started = false;

  void flush() {
    if (!started) return;
    final band = currentBand;
    segments.add(
      HeaderBandLayout<T>(
        band: band,
        offset: currentOffset,
        width: currentWidth,
        columns: List<ColumnLayout<T>>.unmodifiable(currentColumns),
        isContinuation: band != null && !drawn.add(band),
      ),
    );
  }

  for (final column in pane) {
    final band = owner[column.column.field];
    if (!started || !identical(band, currentBand)) {
      flush();
      started = true;
      currentBand = band;
      currentColumns = [column];
      currentOffset = column.offset;
      currentWidth = column.width;
    } else {
      currentColumns.add(column);
      currentWidth += column.width;
    }
  }
  flush();

  return segments;
}

/// Validates [rows] against [columns], returning a message per problem.
///
/// Called from an assertion rather than throwing, because a mistyped field in
/// a header band should be loud in development and harmless in production —
/// the band simply covers fewer columns.
List<String> describeHeaderProblems<T>(
  List<HeaderRow> rows,
  List<GridColumn<T>> columns,
) {
  final known = {for (final c in columns) c.field};
  final problems = <String>[];
  for (var i = 0; i < rows.length; i++) {
    final seen = <String, String>{};
    for (final band in rows[i].bands) {
      if (band.fields.isEmpty) {
        problems.add(
          'Header row $i: band "${band.title}" spans no columns.',
        );
      }
      for (final field in band.fields) {
        if (!known.contains(field)) {
          problems.add(
            'Header row $i: band "${band.title}" names unknown column '
            '"$field".',
          );
        }
        final previous = seen[field];
        if (previous != null) {
          problems.add(
            'Header row $i: column "$field" is covered by both "$previous" '
            'and "${band.title}".',
          );
        } else {
          seen[field] = band.title;
        }
      }
    }
  }
  return problems;
}
