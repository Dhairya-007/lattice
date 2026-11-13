/// Column layout: widths, frozen panes and horizontal windowing.
library;

import 'column.dart';

/// How leftover horizontal space is distributed.
enum ColumnFit {
  /// Keep the declared widths and scroll horizontally.
  none,

  /// Grow every column proportionally to fill the viewport.
  stretch,

  /// Grow only the last column.
  lastColumn,
}

/// One laid-out column: its resolved width and its x position within its pane.
class ColumnLayout<T> {
  const ColumnLayout({
    required this.column,
    required this.width,
    required this.offset,
    required this.index,
  });

  final GridColumn<T> column;
  final double width;

  /// Left edge, measured from the start of the pane this column belongs to.
  final double offset;

  /// Index among the visible columns of the whole grid.
  final int index;

  double get end => offset + width;

  @override
  String toString() => 'ColumnLayout(${column.field}, $width @ $offset)';
}

/// The three horizontal panes of a grid: the columns frozen to the leading
/// edge, the scrolling middle, and the columns frozen to the trailing edge.
///
/// Splitting panes here - rather than inside the widget tree - is what lets
/// frozen columns work identically in every adapter, and keeps the scrolling
/// pane a plain list that can be windowed.
class GridLayout<T> {
  GridLayout({
    required this.leading,
    required this.scrolling,
    required this.trailing,
    required this.viewportWidth,
  });

  final List<ColumnLayout<T>> leading;
  final List<ColumnLayout<T>> scrolling;
  final List<ColumnLayout<T>> trailing;

  final double viewportWidth;

  double get leadingWidth => _extent(leading);
  double get trailingWidth => _extent(trailing);
  double get scrollingWidth => _extent(scrolling);

  /// Width available to the scrolling pane.
  double get scrollViewportWidth {
    final rest = viewportWidth - leadingWidth - trailingWidth;
    return rest < 0 ? 0 : rest;
  }

  /// Total width of every column.
  double get totalWidth => leadingWidth + scrollingWidth + trailingWidth;

  List<ColumnLayout<T>> get allColumns => [...leading, ...scrolling, ...trailing];

  int get columnCount => leading.length + scrolling.length + trailing.length;

  /// Columns of the scrolling pane that intersect the horizontal viewport.
  ///
  /// Wide grids - a hundred columns of a financial blotter - only build the
  /// cells actually on screen.
  List<ColumnLayout<T>> visibleScrollingColumns({
    required double scrollOffset,
    double? viewportWidth,
    int overscan = 1,
  }) {
    final width = viewportWidth ?? scrollViewportWidth;
    if (scrolling.isEmpty || width <= 0) return const [];
    var first = scrolling.length - 1;
    var last = 0;
    for (var i = 0; i < scrolling.length; i++) {
      final c = scrolling[i];
      if (c.end > scrollOffset && c.offset < scrollOffset + width) {
        if (i < first) first = i;
        if (i > last) last = i;
      }
    }
    if (first > last) return const [];
    final from = (first - overscan).clamp(0, scrolling.length - 1);
    final to = (last + overscan).clamp(0, scrolling.length - 1);
    return scrolling.sublist(from, to + 1);
  }

  static double _extent(List<ColumnLayout<Object?>> columns) =>
      columns.isEmpty ? 0 : columns.last.end;
}

/// Resolves [columns] into a [GridLayout] for a viewport of [viewportWidth].
///
/// [widthOverrides] carries interactive resizes, keyed by field, so a user's
/// drag survives a rebuild without mutating the column definitions.
GridLayout<T> computeLayout<T>(
  List<GridColumn<T>> columns, {
  required double viewportWidth,
  Map<String, double> widthOverrides = const {},
  ColumnFit fit = ColumnFit.none,
}) {
  final visible = [
    for (final c in columns)
      if (c.visible) c,
  ];

  double widthOf(GridColumn<T> c) {
    final override = widthOverrides[c.field];
    return c.clampWidth(override ?? c.width);
  }

  var widths = {for (final c in visible) c.field: widthOf(c)};

  final natural = widths.values.fold<double>(0, (a, b) => a + b);
  if (fit != ColumnFit.none && viewportWidth > natural && visible.isNotEmpty) {
    final slack = viewportWidth - natural;
    if (fit == ColumnFit.stretch) {
      // Grow in proportion, then hand any rounding remainder to the last
      // growable column so the panes always add up to the viewport exactly.
      final growable = [
        for (final c in visible)
          if (widths[c.field]! < c.maxWidth) c,
      ];
      final growableExtent =
          growable.fold<double>(0, (a, c) => a + widths[c.field]!);
      if (growableExtent > 0) {
        var distributed = 0.0;
        for (final c in growable) {
          final share = slack * (widths[c.field]! / growableExtent);
          final grown = c.clampWidth(widths[c.field]! + share);
          distributed += grown - widths[c.field]!;
          widths[c.field] = grown;
        }
        final remainder = slack - distributed;
        if (remainder.abs() > 0.01) {
          final last = growable.last;
          widths[last.field] = last.clampWidth(widths[last.field]! + remainder);
        }
      }
    } else {
      final last = visible.last;
      widths[last.field] = last.clampWidth(widths[last.field]! + slack);
    }
  }

  final leading = <ColumnLayout<T>>[];
  final scrolling = <ColumnLayout<T>>[];
  final trailing = <ColumnLayout<T>>[];
  final offsets = <ColumnPin, double>{
    ColumnPin.start: 0,
    ColumnPin.none: 0,
    ColumnPin.end: 0,
  };

  for (var i = 0; i < visible.length; i++) {
    final column = visible[i];
    final width = widths[column.field]!;
    final offset = offsets[column.pin]!;
    final laid = ColumnLayout<T>(
      column: column,
      width: width,
      offset: offset,
      index: i,
    );
    offsets[column.pin] = offset + width;
    switch (column.pin) {
      case ColumnPin.start:
        leading.add(laid);
      case ColumnPin.none:
        scrolling.add(laid);
      case ColumnPin.end:
        trailing.add(laid);
    }
  }

  return GridLayout<T>(
    leading: leading,
    scrolling: scrolling,
    trailing: trailing,
    viewportWidth: viewportWidth,
  );
}
