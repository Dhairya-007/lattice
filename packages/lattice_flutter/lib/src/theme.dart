import 'package:lattice_core/lattice_core.dart';
import 'package:material_ui/material_ui.dart';

/// How much room each row gets.
///
/// Density is the single setting people reach for first on a data grid: the
/// same table is a dashboard at one size and a spreadsheet at another.
enum GridDensity {
  /// Spreadsheet-tight, for scanning a lot of rows at once.
  compact,

  /// The default.
  standard,

  /// Roomy, for touch.
  comfortable,
}

/// Visual configuration for [LatticeDataGrid].
///
/// Defaults are derived from the ambient [ThemeData] so a grid looks at home
/// in an app without being configured, while every surface, line and metric
/// stays overridable for a design system that asks for something specific.
@immutable
class LatticeGridTheme {
  const LatticeGridTheme({
    required this.headerBackground,
    required this.headerForeground,
    required this.rowBackground,
    required this.alternateRowBackground,
    required this.hoveredRowBackground,
    required this.selectedRowBackground,
    required this.selectedCellBackground,
    required this.groupRowBackground,
    required this.footerBackground,
    required this.gridLine,
    required this.frozenPaneLine,
    required this.focusedCellBorder,
    required this.errorColor,
    required this.headerTextStyle,
    required this.cellTextStyle,
    required this.groupTextStyle,
    required this.footerTextStyle,
    this.rowHeight = 40,
    this.headerHeight = 44,
    this.stackedHeaderHeight = 36,
    this.stackedHeaderBackground,
    this.filterRowHeight = 40,
    this.footerHeight = 48,
    this.cellPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.gridLineWidth = 1,
    this.showVerticalGridLines = true,
    this.showHorizontalGridLines = true,
    this.stripeRows = false,
    this.groupIndent = 20,
    this.resizeHandleWidth = 10,
    this.tones = const {},
    this.dataBarOpacity = 0.28,
    this.changeFlashColor,
    this.changeFlashDuration = const Duration(milliseconds: 900),
  });

  /// Builds a theme from the ambient Material theme.
  factory LatticeGridTheme.of(
    BuildContext context, {
    GridDensity density = GridDensity.standard,
  }) {
    return LatticeGridTheme.fromTheme(Theme.of(context), density: density);
  }

  /// Builds a theme from an explicit [ThemeData].
  factory LatticeGridTheme.fromTheme(
    ThemeData theme, {
    GridDensity density = GridDensity.standard,
  }) {
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final text = theme.textTheme;
    return LatticeGridTheme(
      headerBackground: Color.alphaBlend(
        scheme.onSurface.withValues(alpha: isDark ? 0.06 : 0.04),
        scheme.surface,
      ),
      headerForeground: scheme.onSurface,
      rowBackground: scheme.surface,
      alternateRowBackground: Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.02),
        scheme.surface,
      ),
      hoveredRowBackground: Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.04),
        scheme.surface,
      ),
      selectedRowBackground: Color.alphaBlend(
        scheme.primary.withValues(alpha: isDark ? 0.24 : 0.12),
        scheme.surface,
      ),
      selectedCellBackground: Color.alphaBlend(
        scheme.primary.withValues(alpha: isDark ? 0.32 : 0.18),
        scheme.surface,
      ),
      groupRowBackground: Color.alphaBlend(
        scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.05),
        scheme.surface,
      ),
      footerBackground: Color.alphaBlend(
        scheme.onSurface.withValues(alpha: isDark ? 0.06 : 0.03),
        scheme.surface,
      ),
      gridLine: scheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.7),
      frozenPaneLine: scheme.outlineVariant,
      focusedCellBorder: scheme.primary,
      errorColor: scheme.error,
      headerTextStyle: (text.labelLarge ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      cellTextStyle: (text.bodyMedium ?? const TextStyle()).copyWith(
        color: scheme.onSurface,
      ),
      groupTextStyle: (text.bodyMedium ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      footerTextStyle: (text.bodySmall ?? const TextStyle()).copyWith(
        color: scheme.onSurfaceVariant,
      ),
      // Semantic tones, so a rule written once reads correctly in both
      // brightnesses. Lightened in the dark theme, where a saturated colour
      // on a dark surface reads louder than the same colour does on white.
      tones: {
        CellTone.neutral: scheme.onSurfaceVariant,
        CellTone.info: isDark
            ? const Color(0xFF74A9F8)
            : const Color(0xFF1C6FD6),
        CellTone.positive: isDark
            ? const Color(0xFF69C98D)
            : const Color(0xFF17864A),
        CellTone.caution: isDark
            ? const Color(0xFFE5A94E)
            : const Color(0xFFB36A00),
        CellTone.severe: isDark
            ? const Color(0xFFF08A8A)
            : const Color(0xFFC4322F),
      },
      changeFlashColor: scheme.tertiary,
      rowHeight: switch (density) {
        GridDensity.compact => 30,
        GridDensity.standard => 40,
        GridDensity.comfortable => 52,
      },
      headerHeight: switch (density) {
        GridDensity.compact => 34,
        GridDensity.standard => 44,
        GridDensity.comfortable => 56,
      },
      stackedHeaderHeight: switch (density) {
        GridDensity.compact => 28,
        GridDensity.standard => 36,
        GridDensity.comfortable => 46,
      },
      filterRowHeight: switch (density) {
        GridDensity.compact => 34,
        GridDensity.standard => 40,
        GridDensity.comfortable => 46,
      },
      cellPadding: switch (density) {
        GridDensity.compact => const EdgeInsets.symmetric(horizontal: 8),
        GridDensity.standard => const EdgeInsets.symmetric(horizontal: 12),
        GridDensity.comfortable => const EdgeInsets.symmetric(horizontal: 16),
      },
    );
  }

  final Color headerBackground;
  final Color headerForeground;
  final Color rowBackground;
  final Color alternateRowBackground;
  final Color hoveredRowBackground;
  final Color selectedRowBackground;
  final Color selectedCellBackground;
  final Color groupRowBackground;
  final Color footerBackground;

  final Color gridLine;

  /// Line drawn where a frozen pane meets the scrolling one.
  final Color frozenPaneLine;

  final Color focusedCellBorder;
  final Color errorColor;

  final TextStyle headerTextStyle;
  final TextStyle cellTextStyle;
  final TextStyle groupTextStyle;
  final TextStyle footerTextStyle;

  final double rowHeight;
  final double headerHeight;

  /// Height of each stacked header row.
  final double stackedHeaderHeight;

  /// Background for stacked header rows; defaults to [headerBackground].
  final Color? stackedHeaderBackground;
  final double filterRowHeight;
  final double footerHeight;
  final EdgeInsets cellPadding;
  final double gridLineWidth;
  final bool showVerticalGridLines;
  final bool showHorizontalGridLines;

  /// Whether to tint every other row.
  final bool stripeRows;

  /// Extra left padding per group nesting level.
  final double groupIndent;

  /// Width of the invisible drag target at a header's trailing edge.
  final double resizeHandleWidth;

  /// Colour for each semantic [CellTone] produced by a [CellRule].
  ///
  /// The engine decides that a value is severe; this decides what severe
  /// looks like, which is why the mapping lives in the theme.
  final Map<CellTone, Color> tones;

  /// Opacity of a data bar at full width.
  final double dataBarOpacity;

  /// Colour a cell flashes when its value changes, with
  /// `LatticeDataGrid.highlightChanges`.
  final Color? changeFlashColor;

  final Duration changeFlashDuration;

  /// The colour for [tone], or [cellTextStyle]'s colour when unmapped.
  Color toneColor(CellTone tone) =>
      tones[tone] ?? cellTextStyle.color ?? const Color(0xFF000000);

  /// Background tint for a decorated cell, scaled by its intensity.
  ///
  /// Returns null for a neutral or inert decoration, so an undecorated cell
  /// costs no colour blending at all.
  Color? backgroundFor(CellDecoration decoration) {
    if (decoration.tone == CellTone.neutral || decoration.intensity <= 0) {
      return null;
    }
    final color = toneColor(decoration.tone);
    return color.withValues(alpha: 0.05 + 0.22 * decoration.intensity);
  }

  /// Background for a data row, before selection and hover are applied.
  Color backgroundForRow(int index) {
    if (!stripeRows) return rowBackground;
    return index.isEven ? rowBackground : alternateRowBackground;
  }

  LatticeGridTheme copyWith({
    Color? headerBackground,
    Color? headerForeground,
    Color? rowBackground,
    Color? alternateRowBackground,
    Color? hoveredRowBackground,
    Color? selectedRowBackground,
    Color? selectedCellBackground,
    Color? groupRowBackground,
    Color? footerBackground,
    Color? gridLine,
    Color? frozenPaneLine,
    Color? focusedCellBorder,
    Color? errorColor,
    TextStyle? headerTextStyle,
    TextStyle? cellTextStyle,
    TextStyle? groupTextStyle,
    TextStyle? footerTextStyle,
    double? rowHeight,
    double? headerHeight,
    double? stackedHeaderHeight,
    Color? stackedHeaderBackground,
    double? filterRowHeight,
    double? footerHeight,
    EdgeInsets? cellPadding,
    double? gridLineWidth,
    bool? showVerticalGridLines,
    bool? showHorizontalGridLines,
    bool? stripeRows,
    double? groupIndent,
    double? resizeHandleWidth,
    Map<CellTone, Color>? tones,
    double? dataBarOpacity,
    Color? changeFlashColor,
    Duration? changeFlashDuration,
  }) {
    return LatticeGridTheme(
      headerBackground: headerBackground ?? this.headerBackground,
      headerForeground: headerForeground ?? this.headerForeground,
      rowBackground: rowBackground ?? this.rowBackground,
      alternateRowBackground:
          alternateRowBackground ?? this.alternateRowBackground,
      hoveredRowBackground: hoveredRowBackground ?? this.hoveredRowBackground,
      selectedRowBackground:
          selectedRowBackground ?? this.selectedRowBackground,
      selectedCellBackground:
          selectedCellBackground ?? this.selectedCellBackground,
      groupRowBackground: groupRowBackground ?? this.groupRowBackground,
      footerBackground: footerBackground ?? this.footerBackground,
      gridLine: gridLine ?? this.gridLine,
      frozenPaneLine: frozenPaneLine ?? this.frozenPaneLine,
      focusedCellBorder: focusedCellBorder ?? this.focusedCellBorder,
      errorColor: errorColor ?? this.errorColor,
      headerTextStyle: headerTextStyle ?? this.headerTextStyle,
      cellTextStyle: cellTextStyle ?? this.cellTextStyle,
      groupTextStyle: groupTextStyle ?? this.groupTextStyle,
      footerTextStyle: footerTextStyle ?? this.footerTextStyle,
      rowHeight: rowHeight ?? this.rowHeight,
      headerHeight: headerHeight ?? this.headerHeight,
      stackedHeaderHeight: stackedHeaderHeight ?? this.stackedHeaderHeight,
      stackedHeaderBackground:
          stackedHeaderBackground ?? this.stackedHeaderBackground,
      filterRowHeight: filterRowHeight ?? this.filterRowHeight,
      footerHeight: footerHeight ?? this.footerHeight,
      cellPadding: cellPadding ?? this.cellPadding,
      gridLineWidth: gridLineWidth ?? this.gridLineWidth,
      showVerticalGridLines:
          showVerticalGridLines ?? this.showVerticalGridLines,
      showHorizontalGridLines:
          showHorizontalGridLines ?? this.showHorizontalGridLines,
      stripeRows: stripeRows ?? this.stripeRows,
      groupIndent: groupIndent ?? this.groupIndent,
      resizeHandleWidth: resizeHandleWidth ?? this.resizeHandleWidth,
      tones: tones ?? this.tones,
      dataBarOpacity: dataBarOpacity ?? this.dataBarOpacity,
      changeFlashColor: changeFlashColor ?? this.changeFlashColor,
      changeFlashDuration: changeFlashDuration ?? this.changeFlashDuration,
    );
  }
}
