/// Conditional formatting: turning a value into visual emphasis.
///
/// The rules live in the engine, not in the widgets, for the same reason
/// sorting does: deciding that 1 200 ms is "severe" and that it fills 94% of
/// a data bar is a judgement about data, it is testable without a frame, and
/// every adapter should make it identically. What the engine deliberately
/// does **not** decide is what severe looks like - that is a colour, and
/// colours belong to the theme.
library;

import 'compare.dart';

/// The meaning of a cell's emphasis, which an adapter maps to real colours.
///
/// Semantic rather than literal so one rule set reads correctly in light and
/// dark, and so a design system can substitute its own palette.
enum CellTone { neutral, info, positive, caution, severe }

/// How a cell should be emphasised.
///
/// A value type with no colours in it: [tone] says what it means, [intensity]
/// says how strongly, and [bar] asks for a proportional bar behind the text.
class CellDecoration {
  const CellDecoration({
    this.tone = CellTone.neutral,
    this.intensity = 1,
    this.bar,
    this.bold = false,
  }) : assert(intensity >= 0 && intensity <= 1, 'intensity is a 0..1 fraction'),
       assert(
         bar == null || (bar >= 0 && bar <= 1),
         'bar is a 0..1 fraction of the cell width',
       );

  static const CellDecoration none = CellDecoration();

  final CellTone tone;

  /// How strongly to apply [tone], from 0 (not at all) to 1.
  final double intensity;

  /// Fraction of the cell to fill with a bar, or null for no bar.
  final double? bar;

  /// Whether the value should be emphasised in weight as well as colour.
  final bool bold;

  bool get isEmpty => tone == CellTone.neutral && bar == null && !bold;

  CellDecoration copyWith({
    CellTone? tone,
    double? intensity,
    double? bar,
    bool? bold,
  }) {
    return CellDecoration(
      tone: tone ?? this.tone,
      intensity: intensity ?? this.intensity,
      bar: bar ?? this.bar,
      bold: bold ?? this.bold,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CellDecoration &&
      other.tone == tone &&
      other.intensity == intensity &&
      other.bar == bar &&
      other.bold == bold;

  @override
  int get hashCode => Object.hash(tone, intensity, bar, bold);

  @override
  String toString() =>
      'CellDecoration(${tone.name}, intensity: $intensity, bar: $bar)';
}

/// Range of a column's values, so a rule can place one value against the rest.
///
/// Computed once per data revision by the data source, not per cell: a data
/// bar needs the column's minimum and maximum, and recomputing those while
/// scrolling would make scrolling O(rows) per frame.
class ColumnStats {
  const ColumnStats({
    required this.min,
    required this.max,
    required this.count,
    required this.nullCount,
    this.sum,
  });

  static const ColumnStats empty = ColumnStats(
    min: null,
    max: null,
    count: 0,
    nullCount: 0,
  );

  /// Smallest and largest non-null values, by [compareValues].
  final Object? min;
  final Object? max;

  /// Non-null values seen.
  final int count;

  final int nullCount;

  /// Total of the numeric values, when the column held any.
  final num? sum;

  num? get minNumber => min is num ? min! as num : null;
  num? get maxNumber => max is num ? max! as num : null;

  num? get mean =>
      sum == null || count == 0 ? null : sum! / count;

  bool get isEmpty => count == 0;

  /// Where [value] sits between [min] and [max], as 0..1.
  ///
  /// Returns null when the range cannot be measured: a non-numeric column, an
  /// empty one, or one where every value is the same.
  double? fractionOf(Object? value) {
    if (value is! num) return null;
    final low = minNumber;
    final high = maxNumber;
    if (low == null || high == null) return null;
    final span = high - low;
    if (span <= 0) return value == low ? 1 : null;
    final fraction = (value - low) / span;
    return fraction.clamp(0.0, 1.0).toDouble();
  }

  @override
  String toString() => 'ColumnStats($min..$max, $count values)';
}

/// Computes [ColumnStats] for one column's values.
ColumnStats computeColumnStats(Iterable<Object?> values) {
  Object? min;
  Object? max;
  var count = 0;
  var nullCount = 0;
  num? sum;
  for (final value in values) {
    if (value == null) {
      nullCount++;
      continue;
    }
    count++;
    if (min == null || compareValues(value, min) < 0) min = value;
    if (max == null || compareValues(value, max) > 0) max = value;
    if (value is num) sum = (sum ?? 0) + value;
  }
  return ColumnStats(
    min: min,
    max: max,
    count: count,
    nullCount: nullCount,
    sum: sum,
  );
}

/// Decides how one cell should look, given its value and its column's range.
///
/// Rules are pure functions of the value: no row, no index, no build context.
/// That keeps them cheap enough to run for every visible cell on every frame,
/// and testable without a grid.
abstract class CellRule {
  const CellRule();

  /// The emphasis for [value], or null to leave the cell plain.
  CellDecoration? decorate(Object? value, ColumnStats stats);
}

/// Fills part of the cell in proportion to the value's place in the column.
///
/// The spreadsheet "data bar": the cheapest way to make a column of numbers
/// readable at a glance.
class DataBarRule extends CellRule {
  const DataBarRule({
    this.tone = CellTone.info,
    this.fromZero = false,
    this.minimumFraction = 0.02,
  });

  final CellTone tone;

  /// Measures the bar from zero rather than from the column's minimum.
  ///
  /// From zero is honest when the values are counts or amounts; from the
  /// minimum shows more contrast when they are clustered, at the cost of
  /// exaggerating small differences.
  final bool fromZero;

  /// Smallest bar drawn for a non-zero value, so it does not vanish.
  final double minimumFraction;

  @override
  CellDecoration? decorate(Object? value, ColumnStats stats) {
    if (value is! num) return null;
    final double? fraction;
    if (fromZero) {
      final high = stats.maxNumber;
      if (high == null || high <= 0) return null;
      fraction = (value / high).clamp(0.0, 1.0).toDouble();
    } else {
      fraction = stats.fractionOf(value);
    }
    if (fraction == null) return null;
    final shown = fraction == 0
        ? 0.0
        : (fraction < minimumFraction ? minimumFraction : fraction);
    return CellDecoration(tone: tone, intensity: 1, bar: shown);
  }
}

/// Tints the cell by where the value sits in the column's range.
class ColorScaleRule extends CellRule {
  const ColorScaleRule({
    this.low = CellTone.positive,
    this.high = CellTone.severe,
    this.midpoint = 0.5,
    this.reverse = false,
  });

  /// Tone at the bottom and the top of the range.
  final CellTone low;
  final CellTone high;

  /// Fraction at which [low] gives way to [high].
  final double midpoint;

  /// Swaps the ends, for columns where small is bad.
  final bool reverse;

  @override
  CellDecoration? decorate(Object? value, ColumnStats stats) {
    var fraction = stats.fractionOf(value);
    if (fraction == null) return null;
    if (reverse) fraction = 1 - fraction;
    final isHigh = fraction >= midpoint;
    // Intensity ramps from nothing at the midpoint to full at the end, so
    // the middle of a column stays quiet instead of everything being shouted.
    final distance = isHigh
        ? (fraction - midpoint) / (1 - midpoint).clamp(0.0001, 1)
        : (midpoint - fraction) / midpoint.clamp(0.0001, 1);
    return CellDecoration(
      tone: isHigh ? high : low,
      intensity: distance.clamp(0.0, 1.0).toDouble(),
    );
  }
}

/// Applies a tone once the value passes a threshold.
class ThresholdRule extends CellRule {
  const ThresholdRule({
    required this.threshold,
    this.tone = CellTone.severe,
    this.above = true,
    this.bold = false,
  });

  final Object threshold;

  final CellTone tone;

  /// Whether the rule fires above the threshold or below it.
  final bool above;

  final bool bold;

  @override
  CellDecoration? decorate(Object? value, ColumnStats stats) {
    if (value == null) return null;
    final cmp = compareValues(value, threshold);
    final fires = above ? cmp >= 0 : cmp <= 0;
    if (!fires) return null;
    return CellDecoration(tone: tone, bold: bold);
  }
}

/// Maps discrete values to tones, for status and severity columns.
class ValueToneRule extends CellRule {
  const ValueToneRule(this.tones, {this.caseSensitive = false, this.bold = true});

  /// Value to tone, e.g. `{'error': CellTone.severe, 'warn': CellTone.caution}`.
  final Map<Object?, CellTone> tones;

  final bool caseSensitive;
  final bool bold;

  @override
  CellDecoration? decorate(Object? value, ColumnStats stats) {
    if (value == null) return null;
    var tone = tones[value];
    if (tone == null && !caseSensitive && value is String) {
      final lowered = value.toLowerCase();
      for (final entry in tones.entries) {
        final key = entry.key;
        if (key is String && key.toLowerCase() == lowered) {
          tone = entry.value;
          break;
        }
      }
    }
    if (tone == null) return null;
    return CellDecoration(tone: tone, bold: bold);
  }
}

/// Applies the first rule that fires, in order.
///
/// Later rules act as fallbacks, so a threshold can take precedence over a
/// colour scale without either knowing about the other.
class FirstMatchRule extends CellRule {
  const FirstMatchRule(this.rules);

  final List<CellRule> rules;

  @override
  CellDecoration? decorate(Object? value, ColumnStats stats) {
    for (final rule in rules) {
      final decoration = rule.decorate(value, stats);
      if (decoration != null) return decoration;
    }
    return null;
  }
}

/// Merges every rule that fires, later ones winning on conflicts.
///
/// How a data bar and a severity tone combine on the same cell.
class MergedRule extends CellRule {
  const MergedRule(this.rules);

  final List<CellRule> rules;

  @override
  CellDecoration? decorate(Object? value, ColumnStats stats) {
    CellDecoration? merged;
    for (final rule in rules) {
      final decoration = rule.decorate(value, stats);
      if (decoration == null) continue;
      merged = merged == null
          ? decoration
          : merged.copyWith(
              tone: decoration.tone == CellTone.neutral
                  ? merged.tone
                  : decoration.tone,
              intensity: decoration.intensity,
              bar: decoration.bar ?? merged.bar,
              bold: merged.bold || decoration.bold,
            );
    }
    return merged;
  }
}
