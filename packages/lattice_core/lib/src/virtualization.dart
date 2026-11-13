/// Row and column windowing maths.
library;

/// The slice of rows a viewport can see.
class RowWindow {
  const RowWindow({
    required this.firstIndex,
    required this.lastIndex,
    required this.offset,
    required this.totalExtent,
  });

  static const RowWindow empty =
      RowWindow(firstIndex: 0, lastIndex: -1, offset: 0, totalExtent: 0);

  /// First visible row, inclusive.
  final int firstIndex;

  /// Last visible row, inclusive. Less than [firstIndex] when empty.
  final int lastIndex;

  /// Distance from the top of the scrollable content to the top of
  /// [firstIndex], so the adapter can place the window without a per-row
  /// layout pass.
  final double offset;

  /// Height of every row together, i.e. the scrollable extent.
  final double totalExtent;

  int get length => lastIndex < firstIndex ? 0 : lastIndex - firstIndex + 1;

  bool get isEmpty => length == 0;

  Iterable<int> get indices =>
      Iterable<int>.generate(length, (i) => firstIndex + i);

  @override
  String toString() =>
      'RowWindow($firstIndex..$lastIndex, offset $offset of $totalExtent)';
}

/// Maps between scroll offsets and row indices.
///
/// Uniform rows are pure arithmetic. Variable rows (a measured row, an
/// expanded detail panel, a taller group header) are served from a prefix-sum
/// table built once per change and binary-searched, which keeps scrolling
/// O(log n) instead of O(n).
class RowMetrics {
  RowMetrics.uniform({required this.rowCount, required double rowHeight})
      : _rowHeight = rowHeight,
        _offsets = null,
        assert(rowHeight > 0, 'rowHeight must be positive'),
        assert(rowCount >= 0);

  /// Builds metrics from a per-row height function.
  factory RowMetrics.variable({
    required int rowCount,
    required double Function(int index) heightOf,
  }) {
    final offsets = Float64ListLike(rowCount + 1);
    var running = 0.0;
    offsets[0] = 0;
    for (var i = 0; i < rowCount; i++) {
      final h = heightOf(i);
      assert(h > 0, 'row $i has non-positive height $h');
      running += h;
      offsets[i + 1] = running;
    }
    return RowMetrics._(rowCount: rowCount, offsets: offsets);
  }

  RowMetrics._({required this.rowCount, required FloatList offsets})
      : _offsets = offsets,
        _rowHeight = 0;

  final int rowCount;
  final double _rowHeight;
  final FloatList? _offsets;

  bool get isUniform => _offsets == null;

  /// Total height of all rows.
  double get totalExtent =>
      isUniform ? rowCount * _rowHeight : _offsets![rowCount];

  /// Distance from the top of the content to the top of [index].
  double offsetOf(int index) {
    final i = index.clamp(0, rowCount);
    return isUniform ? i * _rowHeight : _offsets![i];
  }

  double heightOf(int index) {
    if (index < 0 || index >= rowCount) return 0;
    return isUniform
        ? _rowHeight
        : _offsets![index + 1] - _offsets![index];
  }

  /// The row containing [offset], clamped to the valid range.
  int indexAt(double offset) {
    if (rowCount == 0) return 0;
    if (offset <= 0) return 0;
    if (offset >= totalExtent) return rowCount - 1;
    if (isUniform) {
      return (offset / _rowHeight).floor().clamp(0, rowCount - 1);
    }
    var low = 0;
    var high = rowCount - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_offsets![mid + 1] <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Rows intersecting a viewport of [viewportExtent] at [scrollOffset].
  ///
  /// [overscan] renders extra rows on each side so that a fast scroll does not
  /// expose blank bands before the next frame.
  RowWindow windowFor({
    required double scrollOffset,
    required double viewportExtent,
    int overscan = 2,
  }) {
    if (rowCount == 0 || viewportExtent <= 0) return RowWindow.empty;
    final first = indexAt(scrollOffset);
    final last = indexAt(scrollOffset + viewportExtent);
    final from = (first - overscan).clamp(0, rowCount - 1);
    final to = (last + overscan).clamp(0, rowCount - 1);
    return RowWindow(
      firstIndex: from,
      lastIndex: to,
      offset: offsetOf(from),
      totalExtent: totalExtent,
    );
  }

  /// Scroll offset that brings [index] fully into a viewport of
  /// [viewportExtent], moving as little as possible.
  double scrollOffsetToReveal(
    int index, {
    required double viewportExtent,
    required double currentOffset,
    double padding = 0,
  }) {
    final top = offsetOf(index) - padding;
    final bottom = offsetOf(index) + heightOf(index) + padding;
    if (top < currentOffset) return top.clamp(0, _maxScroll(viewportExtent));
    if (bottom > currentOffset + viewportExtent) {
      return (bottom - viewportExtent).clamp(0, _maxScroll(viewportExtent));
    }
    return currentOffset;
  }

  double _maxScroll(double viewportExtent) {
    final max = totalExtent - viewportExtent;
    return max < 0 ? 0 : max;
  }
}

/// Minimal growable double list, so the engine needs no `dart:typed_data`
/// specialisation on the web and stays dependency-free.
abstract interface class FloatList {
  double operator [](int index);
  void operator []=(int index, double value);
  int get length;
}

/// Fixed-length [FloatList] backed by a plain [List].
class Float64ListLike implements FloatList {
  Float64ListLike(int length) : _data = List<double>.filled(length, 0);

  final List<double> _data;

  @override
  double operator [](int index) => _data[index];

  @override
  void operator []=(int index, double value) => _data[index] = value;

  @override
  int get length => _data.length;
}
