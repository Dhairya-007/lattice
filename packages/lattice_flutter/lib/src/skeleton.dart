import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// A shimmering placeholder grid, shown while the first page is in flight.
///
/// A spinner tells the user to wait; a skeleton tells them what they are
/// waiting for. It also stops the layout jumping when the rows arrive,
/// because it occupies the shape the grid is about to take.
class LatticeSkeleton extends StatefulWidget {
  const LatticeSkeleton({
    required this.theme,
    required this.columnWidths,
    this.rowCount,
    super.key,
  });

  final LatticeGridTheme theme;

  /// Widths of the columns the real grid will use, so the placeholder has
  /// the same silhouette.
  final List<double> columnWidths;

  /// Rows to draw; defaults to filling the available height.
  final int? rowCount;

  @override
  State<LatticeSkeleton> createState() => _LatticeSkeletonState();
}

class _LatticeSkeletonState extends State<LatticeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows =
            widget.rowCount ??
            (constraints.maxHeight / theme.rowHeight).ceil().clamp(1, 40);
        return ClipRect(
          child: AnimatedBuilder(
            animation: _shimmer,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var row = 0; row < rows; row++)
                    SizedBox(
                      height: theme.rowHeight,
                      child: Row(
                        children: [
                          for (var i = 0; i < widget.columnWidths.length; i++)
                            SizedBox(
                              width: widget.columnWidths[i],
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: theme.cellPadding.left,
                                  vertical: theme.rowHeight * 0.3,
                                ),
                                child: _Bar(
                                  // Vary the widths so it reads as text
                                  // rather than as a loading bar.
                                  widthFactor: _widthFactor(row, i),
                                  progress: _shimmer.value,
                                  // Offset per cell so the sheen travels
                                  // across the grid instead of pulsing.
                                  phase: (row * 0.06 + i * 0.12) % 1,
                                  color: theme.gridLine,
                                  highlight: theme.hoveredRowBackground,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Deterministic pseudo-random width, so the skeleton does not change
  /// shape on every frame.
  static double _widthFactor(int row, int column) {
    final seed = (row * 31 + column * 17) % 7;
    return 0.45 + seed * 0.08;
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.widthFactor,
    required this.progress,
    required this.phase,
    required this.color,
    required this.highlight,
  });

  final double widthFactor;
  final double progress;
  final double phase;
  final Color color;
  final Color highlight;

  @override
  Widget build(BuildContext context) {
    final t = (progress + phase) % 1;
    // A triangle wave: brighten to the midpoint, then fade back.
    final sheen = t < 0.5 ? t * 2 : (1 - t) * 2;
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(color, highlight, sheen * 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
