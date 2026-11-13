/// Column aggregations used by group rows and the summary footer.
library;

import 'compare.dart';

/// Built-in aggregate functions.
enum AggregateType { count, countDistinct, sum, average, min, max, first, last, custom }

/// Computes one aggregate over the values of one column.
class Aggregation {
  const Aggregation(
    this.field, {
    this.type = AggregateType.sum,
    this.compute,
    String? id,
    this.label,
  })  : _id = id,
        assert(
          type != AggregateType.custom || compute != null,
          'AggregateType.custom requires a compute function',
        );

  const Aggregation.count(String field, {String? label})
      : this(field, type: AggregateType.count, label: label);
  const Aggregation.sum(String field, {String? label})
      : this(field, type: AggregateType.sum, label: label);
  const Aggregation.average(String field, {String? label})
      : this(field, type: AggregateType.average, label: label);
  const Aggregation.min(String field, {String? label})
      : this(field, type: AggregateType.min, label: label);
  const Aggregation.max(String field, {String? label})
      : this(field, type: AggregateType.max, label: label);

  /// Column whose values are aggregated.
  final String field;

  final AggregateType type;

  /// Reducer for [AggregateType.custom]. Receives every value of [field] in
  /// the group, nulls included.
  final Object? Function(List<Object?> values)? compute;

  final String? _id;

  /// Text a UI adapter shows beside the result.
  final String? label;

  /// Key this aggregate is stored under in [AggregateResult].
  String get id => _id ?? '$field.${type.name}';

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
    out[aggregation.id] =
        aggregation.apply([for (final row in rows) read(row, aggregation.field)]);
  }
  return AggregateResult(out);
}
