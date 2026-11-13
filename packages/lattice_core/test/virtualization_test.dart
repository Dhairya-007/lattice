import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

void main() {
  group('uniform metrics', () {
    final metrics = RowMetrics.uniform(rowCount: 1000, rowHeight: 40);

    test('total extent is rows times height', () {
      expect(metrics.totalExtent, 40000);
      expect(metrics.isUniform, isTrue);
    });

    test('offsets and heights are arithmetic', () {
      expect(metrics.offsetOf(0), 0);
      expect(metrics.offsetOf(10), 400);
      expect(metrics.heightOf(10), 40);
    });

    test('indexAt resolves the row under an offset', () {
      expect(metrics.indexAt(0), 0);
      expect(metrics.indexAt(39.9), 0);
      expect(metrics.indexAt(40), 1);
      expect(metrics.indexAt(405), 10);
    });

    test('indexAt clamps outside the content', () {
      expect(metrics.indexAt(-100), 0);
      expect(metrics.indexAt(1e9), 999);
    });

    test('a window covers the viewport plus overscan', () {
      final window = metrics.windowFor(
        scrollOffset: 400,
        viewportExtent: 200,
        overscan: 2,
      );
      expect(window.firstIndex, 8);
      expect(window.lastIndex, 17);
      expect(window.offset, 320);
      expect(window.totalExtent, 40000);
      expect(window.length, 10);
    });

    test('a window never runs past the ends', () {
      final top = metrics.windowFor(scrollOffset: 0, viewportExtent: 100);
      expect(top.firstIndex, 0);
      final bottom =
          metrics.windowFor(scrollOffset: 39900, viewportExtent: 100);
      expect(bottom.lastIndex, 999);
    });

    test('indices enumerate exactly the visible rows', () {
      final window = metrics.windowFor(
        scrollOffset: 0,
        viewportExtent: 80,
        overscan: 0,
      );
      expect(window.indices, [0, 1, 2]);
    });
  });

  group('empty and degenerate metrics', () {
    test('no rows yields an empty window', () {
      final metrics = RowMetrics.uniform(rowCount: 0, rowHeight: 40);
      final window = metrics.windowFor(scrollOffset: 0, viewportExtent: 500);
      expect(window.isEmpty, isTrue);
      expect(metrics.totalExtent, 0);
    });

    test('a zero-height viewport yields an empty window', () {
      final metrics = RowMetrics.uniform(rowCount: 10, rowHeight: 40);
      expect(
        metrics.windowFor(scrollOffset: 0, viewportExtent: 0).isEmpty,
        isTrue,
      );
    });

    test('heights outside the range are zero', () {
      final metrics = RowMetrics.uniform(rowCount: 3, rowHeight: 40);
      expect(metrics.heightOf(-1), 0);
      expect(metrics.heightOf(3), 0);
    });
  });

  group('variable metrics', () {
    // 0:20, 1:40, 2:60, 3:80, 4:100 -> offsets 0, 20, 60, 120, 200, 300
    final metrics = RowMetrics.variable(
      rowCount: 5,
      heightOf: (i) => 20.0 * (i + 1),
    );

    test('accumulates per-row heights', () {
      expect(metrics.isUniform, isFalse);
      expect(metrics.totalExtent, 300);
      expect(metrics.offsetOf(0), 0);
      expect(metrics.offsetOf(3), 120);
      expect(metrics.heightOf(3), 80);
    });

    test('binary search finds the row at an offset and at boundaries', () {
      expect(metrics.indexAt(0), 0);
      expect(metrics.indexAt(19), 0);
      expect(metrics.indexAt(20), 1);
      expect(metrics.indexAt(59), 1);
      expect(metrics.indexAt(60), 2);
      expect(metrics.indexAt(299), 4);
    });

    test('a window reports the offset of its first row', () {
      final window = metrics.windowFor(
        scrollOffset: 130,
        viewportExtent: 50,
        overscan: 0,
      );
      expect(window.firstIndex, 3);
      expect(window.offset, 120);
    });

    test('every offset in the content maps to a row that contains it', () {
      for (var offset = 0.0; offset < 300; offset += 7) {
        final index = metrics.indexAt(offset);
        expect(metrics.offsetOf(index), lessThanOrEqualTo(offset));
        expect(
          metrics.offsetOf(index) + metrics.heightOf(index),
          greaterThan(offset),
        );
      }
    });
  });

  group('scrollOffsetToReveal', () {
    final metrics = RowMetrics.uniform(rowCount: 100, rowHeight: 40);

    test('scrolls up to a row above the viewport', () {
      expect(
        metrics.scrollOffsetToReveal(
          2,
          viewportExtent: 400,
          currentOffset: 800,
        ),
        80,
      );
    });

    test('scrolls down just far enough for a row below the viewport', () {
      expect(
        metrics.scrollOffsetToReveal(
          20,
          viewportExtent: 400,
          currentOffset: 0,
        ),
        440,
      );
    });

    test('does not move when the row is already visible', () {
      expect(
        metrics.scrollOffsetToReveal(
          5,
          viewportExtent: 400,
          currentOffset: 100,
        ),
        100,
      );
    });

    test('never scrolls past the ends', () {
      expect(
        metrics.scrollOffsetToReveal(
          0,
          viewportExtent: 400,
          currentOffset: 10,
          padding: 100,
        ),
        0,
      );
      expect(
        metrics.scrollOffsetToReveal(
          99,
          viewportExtent: 400,
          currentOffset: 0,
        ),
        metrics.totalExtent - 400,
      );
    });
  });
}
