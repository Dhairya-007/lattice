/// Declarative, serialisable filter model.
library;

import 'compare.dart';

/// Comparison applied by a [FilterCondition].
enum FilterOperator {
  equals,
  notEquals,
  contains,
  notContains,
  startsWith,
  endsWith,
  greaterThan,
  greaterOrEqual,
  lessThan,
  lessOrEqual,
  between,
  isIn,
  isNull,
  isNotNull,
  isEmpty,
  isNotEmpty,
}

/// How the children of a [FilterGroup] combine.
enum FilterJoin { and, or }

/// Common interface of [FilterCondition] and [FilterGroup].
///
/// Filters form a tree, are value types, and serialise to plain JSON so a
/// saved view can round-trip through storage or an HTTP backend.
sealed class Filter {
  const Filter();

  /// Whether [row] (as a field -> value map) satisfies this filter.
  bool matches(Map<String, Object?> row);

  /// Fields referenced anywhere in this subtree.
  Set<String> get fields;

  Map<String, Object?> toJson();

  /// Rebuilds a filter tree produced by [toJson].
  static Filter fromJson(Map<String, Object?> json) {
    if (json['join'] != null) return FilterGroup.fromJson(json);
    return FilterCondition.fromJson(json);
  }
}

/// A single `field operator value` test.
class FilterCondition extends Filter {
  const FilterCondition({
    required this.field,
    required this.operator,
    this.value,
    this.secondValue,
    this.caseSensitive = false,
  });

  final String field;
  final FilterOperator operator;

  /// Right-hand operand. For [FilterOperator.isIn] this is an [Iterable].
  final Object? value;

  /// Upper bound, used only by [FilterOperator.between].
  final Object? secondValue;

  /// Whether text comparisons respect case. Defaults to case-insensitive,
  /// which is what users expect of a filter row.
  final bool caseSensitive;

  @override
  Set<String> get fields => {field};

  /// Whether this condition is inert and should be dropped from a query.
  ///
  /// A filter row the user has not filled in yet must not hide every row.
  bool get isEmpty {
    switch (operator) {
      case FilterOperator.isNull:
      case FilterOperator.isNotNull:
      case FilterOperator.isEmpty:
      case FilterOperator.isNotEmpty:
        return false;
      case FilterOperator.between:
        return value == null || secondValue == null;
      case FilterOperator.isIn:
        return value == null || (value as Iterable).isEmpty;
      default:
        return value == null || (value is String && (value as String).isEmpty);
    }
  }

  @override
  bool matches(Map<String, Object?> row) {
    if (isEmpty) return true;
    final actual = row[field];
    switch (operator) {
      case FilterOperator.equals:
        return _compare(actual, value) == 0;
      case FilterOperator.notEquals:
        return _compare(actual, value) != 0;
      case FilterOperator.contains:
        return _text(actual).contains(_text(value));
      case FilterOperator.notContains:
        return !_text(actual).contains(_text(value));
      case FilterOperator.startsWith:
        return _text(actual).startsWith(_text(value));
      case FilterOperator.endsWith:
        return _text(actual).endsWith(_text(value));
      case FilterOperator.greaterThan:
        return actual != null && _compare(actual, value) > 0;
      case FilterOperator.greaterOrEqual:
        return actual != null && _compare(actual, value) >= 0;
      case FilterOperator.lessThan:
        return actual != null && _compare(actual, value) < 0;
      case FilterOperator.lessOrEqual:
        return actual != null && _compare(actual, value) <= 0;
      case FilterOperator.between:
        if (actual == null) return false;
        return _compare(actual, value) >= 0 &&
            _compare(actual, secondValue) <= 0;
      case FilterOperator.isIn:
        return (value as Iterable).any((v) => _compare(actual, v) == 0);
      case FilterOperator.isNull:
        return actual == null;
      case FilterOperator.isNotNull:
        return actual != null;
      case FilterOperator.isEmpty:
        return actual == null || _text(actual).isEmpty;
      case FilterOperator.isNotEmpty:
        return actual != null && _text(actual).isNotEmpty;
    }
  }

  int _compare(Object? a, Object? b) =>
      caseSensitive ? compareValues(a, b) : compareValuesCaseInsensitive(a, b);

  String _text(Object? v) {
    final s = v == null ? '' : '$v';
    return caseSensitive ? s : s.toLowerCase();
  }

  FilterCondition copyWith({
    String? field,
    FilterOperator? operator,
    Object? value = _unset,
    Object? secondValue = _unset,
    bool? caseSensitive,
  }) {
    return FilterCondition(
      field: field ?? this.field,
      operator: operator ?? this.operator,
      value: value == _unset ? this.value : value,
      secondValue: secondValue == _unset ? this.secondValue : secondValue,
      caseSensitive: caseSensitive ?? this.caseSensitive,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'field': field,
        'op': operator.name,
        if (value != null)
          'value': value is Iterable ? (value as Iterable).toList() : value,
        if (secondValue != null) 'secondValue': secondValue,
        if (caseSensitive) 'caseSensitive': true,
      };

  static FilterCondition fromJson(Map<String, Object?> json) {
    return FilterCondition(
      field: json['field']! as String,
      operator: FilterOperator.values.firstWhere(
        (o) => o.name == json['op'],
        orElse: () =>
            throw ArgumentError('Unknown filter operator ${json['op']}'),
      ),
      value: json['value'],
      secondValue: json['secondValue'],
      caseSensitive: json['caseSensitive'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FilterCondition &&
      other.field == field &&
      other.operator == operator &&
      other.value == value &&
      other.secondValue == secondValue &&
      other.caseSensitive == caseSensitive;

  @override
  int get hashCode =>
      Object.hash(field, operator, value, secondValue, caseSensitive);

  @override
  String toString() => '$field ${operator.name} $value';
}

/// Combines child filters with [FilterJoin.and] or [FilterJoin.or].
class FilterGroup extends Filter {
  const FilterGroup(this.children, {this.join = FilterJoin.and});

  const FilterGroup.and(List<Filter> children) : this(children);
  const FilterGroup.or(List<Filter> children)
      : this(children, join: FilterJoin.or);

  final List<Filter> children;
  final FilterJoin join;

  @override
  Set<String> get fields => children.expand((c) => c.fields).toSet();

  @override
  bool matches(Map<String, Object?> row) {
    if (children.isEmpty) return true;
    return join == FilterJoin.and
        ? children.every((c) => c.matches(row))
        : children.any((c) => c.matches(row));
  }

  @override
  Map<String, Object?> toJson() => {
        'join': join.name,
        'children': children.map((c) => c.toJson()).toList(),
      };

  static FilterGroup fromJson(Map<String, Object?> json) {
    return FilterGroup(
      ((json['children'] ?? const []) as List)
          .cast<Map<String, Object?>>()
          .map(Filter.fromJson)
          .toList(),
      join: json['join'] == 'or' ? FilterJoin.or : FilterJoin.and,
    );
  }

  @override
  String toString() => '(${children.join(' ${join.name.toUpperCase()} ')})';
}

const Object _unset = Object();
