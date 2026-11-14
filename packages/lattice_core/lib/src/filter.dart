/// Declarative, serialisable filter model.
library;

import 'column.dart';
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

/// What a [FilterOperator] needs from the user before it means anything.
extension FilterOperatorInput on FilterOperator {
  /// Whether the operator takes a value at all.
  ///
  /// An adapter reads this to decide whether to show an input next to the
  /// operator: `is empty` has nothing to type into.
  bool get needsValue {
    switch (this) {
      case FilterOperator.isNull:
      case FilterOperator.isNotNull:
      case FilterOperator.isEmpty:
      case FilterOperator.isNotEmpty:
        return false;
      default:
        return true;
    }
  }

  /// Whether the operator takes a second value, i.e. it is a range.
  bool get needsSecondValue => this == FilterOperator.between;

  /// Whether the operator takes a set of values rather than one.
  bool get needsValueSet => this == FilterOperator.isIn;

  /// A short English label, as a starting point for an adapter's menu.
  ///
  /// Shipped because every adapter needs one and writing the same switch in
  /// each of them is how they drift apart. Localised UIs map the enum
  /// themselves rather than using this.
  String get defaultLabel {
    switch (this) {
      case FilterOperator.equals:
        return 'equals';
      case FilterOperator.notEquals:
        return 'does not equal';
      case FilterOperator.contains:
        return 'contains';
      case FilterOperator.notContains:
        return 'does not contain';
      case FilterOperator.startsWith:
        return 'starts with';
      case FilterOperator.endsWith:
        return 'ends with';
      case FilterOperator.greaterThan:
        return 'is greater than';
      case FilterOperator.greaterOrEqual:
        return 'is at least';
      case FilterOperator.lessThan:
        return 'is less than';
      case FilterOperator.lessOrEqual:
        return 'is at most';
      case FilterOperator.between:
        return 'is between';
      case FilterOperator.isIn:
        return 'is one of';
      case FilterOperator.isNull:
        return 'is blank';
      case FilterOperator.isNotNull:
        return 'is not blank';
      case FilterOperator.isEmpty:
        return 'is empty';
      case FilterOperator.isNotEmpty:
        return 'is not empty';
    }
  }
}

/// The operators worth offering for a column of [type], most useful first.
///
/// [ColumnType] has always claimed to drive this, but the set lived in
/// whichever adapter needed it, as a switch each one wrote again. It belongs
/// here: a date column offering `starts with` is a bug in the engine's model
/// of the column, not in the widget that drew the menu.
///
/// The first entry is the sensible default for a fresh filter row.
List<FilterOperator> operatorsFor(ColumnType type) {
  switch (type) {
    case ColumnType.text:
    case ColumnType.custom:
      return const [
        FilterOperator.contains,
        FilterOperator.notContains,
        FilterOperator.equals,
        FilterOperator.notEquals,
        FilterOperator.startsWith,
        FilterOperator.endsWith,
        FilterOperator.isIn,
        FilterOperator.isEmpty,
        FilterOperator.isNotEmpty,
      ];
    case ColumnType.number:
      return const [
        FilterOperator.equals,
        FilterOperator.notEquals,
        FilterOperator.greaterThan,
        FilterOperator.greaterOrEqual,
        FilterOperator.lessThan,
        FilterOperator.lessOrEqual,
        FilterOperator.between,
        FilterOperator.isIn,
        FilterOperator.isNull,
        FilterOperator.isNotNull,
      ];
    case ColumnType.date:
      return const [
        FilterOperator.equals,
        FilterOperator.notEquals,
        FilterOperator.greaterThan,
        FilterOperator.lessThan,
        FilterOperator.between,
        FilterOperator.isNull,
        FilterOperator.isNotNull,
      ];
    case ColumnType.boolean:
      return const [
        FilterOperator.equals,
        FilterOperator.isNull,
        FilterOperator.isNotNull,
      ];
  }
}

/// Common interface of [FilterCondition] and [FilterGroup].
///
/// Filters form a tree, are value types, and serialise to plain JSON so a
/// saved view can round-trip through storage or an HTTP backend.
sealed class Filter {
  const Filter();

  /// Whether [row] (as a field -> value map) satisfies this filter.
  bool matches(Map<String, Object?> row) => matchesRow((field) => row[field]);

  /// Whether a row satisfies this filter, reading values through [read].
  ///
  /// The reader form exists so that filtering a wide table does not allocate
  /// a map per row: at 50k rows that allocation dominated the filter itself.
  bool matchesRow(Object? Function(String field) read);

  /// A stable string identifying this filter, for use as a cache key.
  ///
  /// Two filters with the same fingerprint select the same rows. It is not a
  /// serialisation format - use [toJson] for that - and may change shape
  /// between versions.
  String get fingerprint;

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
  String get fingerprint =>
      '$field|${operator.name}|$value|$secondValue|$caseSensitive';

  @override
  bool matchesRow(Object? Function(String field) read) {
    if (isEmpty) return true;
    final actual = read(field);
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
  String get fingerprint =>
      '(${children.map((c) => c.fingerprint).join(join == FilterJoin.and ? '&' : '|')})';

  @override
  bool matchesRow(Object? Function(String field) read) {
    if (children.isEmpty) return true;
    if (join == FilterJoin.and) {
      for (final child in children) {
        if (!child.matchesRow(read)) return false;
      }
      return true;
    }
    for (final child in children) {
      if (child.matchesRow(read)) return true;
    }
    return false;
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
