/// Column aggregations used by group rows and the summary footer.
library;

import 'column.dart';
import 'compare.dart';

/// Built-in aggregate functions.
enum AggregateType {
  count,
  countDistinct,
  sum,
  average,
  min,
  max,
  first,
  last,
  custom
}

/// Computes one aggregate over the values of one column.
class Aggregation {
  const Aggregation(
    this.field, {
    this.type = AggregateType.sum,
    this.compute,
    String? id,
    this.label,
    this.format,
  })  : _id = id,
        assert(
          type != AggregateType.custom || compute != null,
          'AggregateType.custom requires a compute function',
        );

  const Aggregation.count(String field, {String? label, ValueFormatter? format})
      : this(field, type: AggregateType.count, label: label, format: format);
  const Aggregation.sum(String field, {String? label, ValueFormatter? format})
      : this(field, type: AggregateType.sum, label: label, format: format);
  const Aggregation.average(String field,
      {String? label, ValueFormatter? format})
      : this(field, type: AggregateType.average, label: label, format: format);
  const Aggregation.min(String field, {String? label, ValueFormatter? format})
      : this(field, type: AggregateType.min, label: label, format: format);
  const Aggregation.max(String field, {String? label, ValueFormatter? format})
      : this(field, type: AggregateType.max, label: label, format: format);

  /// Column whose values are aggregated.
  final String field;

  final AggregateType type;

  /// Reducer for [AggregateType.custom]. Receives every value of [field] in
  /// the group, nulls included.
  final Object? Function(List<Object?> values)? compute;

  final String? _id;

  /// Text a UI adapter shows beside the result.
  final String? label;

  /// Formats this aggregate's result for display.
  ///
  /// An aggregate's result is not in the same units as the column it came
  /// from: a count of prices is a number of rows, not an amount of money, so
  /// the column's own formatter is the wrong one to use and an adapter that
  /// reached for it had to special-case count against sum. Set this to say
  /// how the result reads - a currency, a percentage, "3 items".
  final ValueFormatter? format;

  /// Key this aggregate is stored under in [AggregateResult].
  String get id => _id ?? '$field.${type.name}';

  /// A stable string identifying what this aggregate computes, for use as a
  /// cache key.
  ///
  /// The reducer is part of it, because two custom aggregations with the same
  /// id and different functions do not compute the same thing.
  String get fingerprint => '$id:${type.name}:$field:${compute?.hashCode ?? 0}';

  /// This aggregate's result as display text.
  ///
  /// Without a [format], an integer prints as itself and a fractional result
  /// to two decimal places, because an average of integers is a double and
  /// `23.333333333333332` in a footer cell is noise rather than precision.
  /// A null result - an empty group, or one where every value was null -
  /// prints as empty rather than as `0`, matching what [apply] returns.
  String formatted(Object? value) {
    final formatter = format;
    if (formatter != null) return formatter(value);
    if (value == null) return '';
    if (value is int) return '$value';
    if (value is double) {
      if (value.isNaN || value.isInfinite) return '$value';
      return value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(2);
    }
    return '$value';
  }

  /// Reduces [values] to a single result.
  ///
  /// Nulls are skipped by the numeric and extremum aggregates, matching SQL,
  /// so an empty or all-null group yields `null` rather than `0`.
  Object? apply(List<Object?> values) {
    switch (type) {
      case AggregateType.count:
        return values.length;
      case AggregateType.countDistinct:
        return values.toSet().length;
      case AggregateType.sum:
        final nums = _numbers(values);
        if (nums.isEmpty) return null;
        return nums.fold<num>(0, (a, b) => a + b);
      case AggregateType.average:
        final nums = _numbers(values);
        if (nums.isEmpty) return null;
        return nums.fold<num>(0, (a, b) => a + b) / nums.length;
      case AggregateType.min:
        return _extremum(values, min: true);
      case AggregateType.max:
        return _extremum(values, min: false);
      case AggregateType.first:
        return values.isEmpty ? null : values.first;
      case AggregateType.last:
        return values.isEmpty ? null : values.last;
      case AggregateType.custom:
        return compute!(values);
    }
  }

  static List<num> _numbers(List<Object?> values) {
    final out = <num>[];
    for (final v in values) {
      if (v is num) {
        out.add(v);
      } else if (v is String) {
        final parsed = num.tryParse(v);
        if (parsed != null) out.add(parsed);
      }
    }
    return out;
  }

  static Object? _extremum(List<Object?> values, {required bool min}) {
    Object? best;
    for (final v in values) {
      if (v == null) continue;
      if (best == null) {
        best = v;
        continue;
      }
      final cmp = compareValues(v, best);
      if (min ? cmp < 0 : cmp > 0) best = v;
    }
    return best;
  }

  @override
  bool operator ==(Object other) =>
      other is Aggregation && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() => '${type.name}($field)';
}

/// Aggregate results for one group or for the whole grid, keyed by
/// [Aggregation.id].
class AggregateResult {
  const AggregateResult(this._values);

  const AggregateResult.empty() : _values = const {};

  final Map<String, Object?> _values;

  Object? operator [](String id) => _values[id];

  Object? of(Aggregation aggregation) => _values[aggregation.id];

  bool get isEmpty => _values.isEmpty;

  Map<String, Object?> get asMap => Map.unmodifiable(_values);

  @override
  String toString() => 'AggregateResult($_values)';
}

/// Runs every aggregation in [aggregations] over [rows].
AggregateResult computeAggregates<T>(
  List<T> rows,
  List<Aggregation> aggregations,
  Object? Function(T row, String field) read,
) {
  if (aggregations.isEmpty) return const AggregateResult.empty();
  final out = <String, Object?>{};
  for (final aggregation in aggregations) {
    out[aggregation.id] = aggregation
        .apply([for (final row in rows) read(row, aggregation.field)]);
  }
  return AggregateResult(out);
}
