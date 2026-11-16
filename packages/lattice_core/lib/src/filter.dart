/// Declarative, serialisable filter model.
library;

import 'dart:collection';

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

  /// Prepares this filter to be run over many rows.
  ///
  /// Everything that depends only on the filter - folding a needle, building
  /// a set out of an `isIn` list, coercing an operand to the column's type -
  /// happens once here instead of once per row. [matchesRow] stays correct on
  /// its own for a one-off test; a pipeline that walks 50k rows compiles
  /// first, which is what turns `isIn` over 1,000 values from 1.9s into a
  /// hash lookup per row.
  ///
  /// [types] maps a field to its [ColumnType], so that a `'50'` typed into a
  /// number column's filter compares as 50 rather than as text. A field
  /// missing from the map is left uncoerced.
  CompiledFilter compile({Map<String, ColumnType> types = const {}});

  Map<String, Object?> toJson();

  /// Rebuilds a filter tree produced by [toJson].
  ///
  /// [warnings], when given, collects a line per child that could not be
  /// read instead of failing the whole tree; a malformed *leaf* still throws
  /// a [FormatException], which is what the group above it catches.
  static Filter fromJson(
    Map<String, Object?> json, {
    List<String>? warnings,
  }) {
    if (json['join'] != null) {
      return FilterGroup.fromJson(json, warnings: warnings);
    }
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
    this.dateOnly = false,
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

  /// Whether a [DateTime] comparison ignores the time of day.
  ///
  /// `equals` against a date column otherwise needs the exact instant, so
  /// "orders on 1 June" matched nothing unless every row happened to be
  /// stamped midnight. With this set, both sides are truncated to their
  /// calendar day before comparing, which also makes `between` cover both
  /// of its end days.
  final bool dateOnly;

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
        // A value that is not a list at all is a malformed condition, not a
        // condition that hides every row: restoring a corrupt saved view
        // used to throw from here.
        final values = value;
        if (values is Iterable) return values.isEmpty;
        return true;
      default:
        return value == null || (value is String && (value as String).isEmpty);
    }
  }

  @override
  String get fingerprint => '$field|${operator.name}|'
      '${value is Iterable ? (value as Iterable).join('\u0001') : value}|'
      '$secondValue|$caseSensitive|$dateOnly';

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
        // A range typed backwards is still a range. Comparing against the
        // bounds in the order they were given matched nothing at all, which
        // reads as "no rows" rather than as "you typed it the other way".
        final low = _compare(value, secondValue) <= 0 ? value : secondValue;
        final high = _compare(value, secondValue) <= 0 ? secondValue : value;
        return _compare(actual, low) >= 0 && _compare(actual, high) <= 0;
      case FilterOperator.isIn:
        final values = value;
        if (values is! Iterable) return true;
        return values.any((v) => _compare(actual, v) == 0);
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

  @override
  CompiledFilter compile({Map<String, ColumnType> types = const {}}) =>
      compileCondition(this, types[field]);

  /// Compares two operands the way this condition's flags ask for.
  ///
  /// A case-insensitive comparison must *not* break a folded tie with the
  /// exact comparison the way a sort does: `equals: 'apple'` against
  /// `'Apple'` is a match, and a `>=` that calls two values equal and then
  /// excludes one of them is simply wrong.
  int _compare(Object? a, Object? b) {
    if (dateOnly && (a is DateTime || b is DateTime)) {
      return compareValues(_truncate(a), _truncate(b));
    }
    return caseSensitive ? compareValues(a, b) : compareValuesFolded(a, b);
  }

  static Object? _truncate(Object? value) =>
      value is DateTime ? DateTime(value.year, value.month, value.day) : value;

  String _text(Object? v) {
    final s = v == null ? '' : '$v';
    return caseSensitive ? s : foldText(s);
  }

  FilterCondition copyWith({
    String? field,
    FilterOperator? operator,
    Object? value = _unset,
    Object? secondValue = _unset,
    bool? caseSensitive,
    bool? dateOnly,
  }) {
    return FilterCondition(
      field: field ?? this.field,
      operator: operator ?? this.operator,
      value: value == _unset ? this.value : value,
      secondValue: secondValue == _unset ? this.secondValue : secondValue,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      dateOnly: dateOnly ?? this.dateOnly,
    );
  }

  /// JSON for a saved view.
  ///
  /// Operands carry their type: a [DateTime] is written as
  /// `{"$date": "<iso>"}` and a [BigInt] as `{"$bigint": "<digits>"}`.
  /// Writing a `DateTime` straight through made `jsonEncode` throw, and
  /// writing it as a bare string made the operand come back as text, so a
  /// restored date filter compared instants against ISO strings and matched
  /// the wrong rows.
  @override
  Map<String, Object?> toJson() => {
        'field': field,
        'op': operator.name,
        if (value != null) 'value': encodeFilterOperand(value),
        if (secondValue != null)
          'secondValue': encodeFilterOperand(secondValue),
        if (caseSensitive) 'caseSensitive': true,
        if (dateOnly) 'dateOnly': true,
      };

  /// Rebuilds a condition produced by [toJson].
  ///
  /// Throws a [FormatException] for a document this cannot read, rather than
  /// a [TypeError] from a null check: a corrupt saved view is a document the
  /// caller can report on, not a crash.
  static FilterCondition fromJson(Map<String, Object?> json) {
    final field = json['field'];
    if (field is! String || field.isEmpty) {
      throw FormatException('A filter needs a non-empty "field"', json);
    }
    final name = json['op'];
    final operator = FilterOperator.values.firstWhere(
      (o) => o.name == name,
      orElse: () =>
          throw FormatException('Unknown filter operator: $name', json),
    );
    var value = decodeFilterOperand(json['value']);
    if (operator == FilterOperator.isIn && value != null && value is! List) {
      // One value where a list belongs is readable: treat it as a set of one
      // rather than refusing the whole view.
      value = [value];
    }
    return FilterCondition(
      field: field,
      operator: operator,
      value: value,
      secondValue: decodeFilterOperand(json['secondValue']),
      caseSensitive: json['caseSensitive'] == true,
      dateOnly: json['dateOnly'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FilterCondition &&
      other.field == field &&
      other.operator == operator &&
      _operandsEqual(other.value, value) &&
      _operandsEqual(other.secondValue, secondValue) &&
      other.caseSensitive == caseSensitive &&
      other.dateOnly == dateOnly;

  @override
  int get hashCode => Object.hash(
        field,
        operator,
        value is Iterable ? Object.hashAll(value as Iterable) : value,
        secondValue,
        caseSensitive,
        dateOnly,
      );

  /// Two operands are the same when they are equal, or when both are lists of
  /// equal values.
  ///
  /// An `isIn` condition holds a list, and two lists with the same contents
  /// are not `==` in Dart - so two conditions that select exactly the same
  /// rows compared unequal, which defeated every cache keyed on a filter and
  /// made the filter row rebuild on every keystroke.
  static bool _operandsEqual(Object? a, Object? b) {
    if (a is Iterable && b is Iterable) {
      final left = a.toList();
      final right = b.toList();
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (left[i] != right[i]) return false;
      }
      return true;
    }
    return a == b;
  }

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
  CompiledFilter compile({Map<String, ColumnType> types = const {}}) {
    if (children.isEmpty) return const _AlwaysTrue();
    final compiled = [for (final c in children) c.compile(types: types)];
    return join == FilterJoin.and
        ? _CompiledAnd(compiled)
        : _CompiledOr(compiled);
  }

  @override
  Map<String, Object?> toJson() => {
        'join': join.name,
        'children': children.map((c) => c.toJson()).toList(),
      };

  /// Rebuilds a group produced by [toJson], skipping children it cannot read.
  ///
  /// A saved view is a user's own work read back by a later build, so one
  /// unreadable condition drops out of the tree rather than taking the whole
  /// view with it. [warnings], when given, collects what was skipped.
  static FilterGroup fromJson(
    Map<String, Object?> json, {
    List<String>? warnings,
  }) {
    final raw = json['children'];
    final children = <Filter>[];
    if (raw is List) {
      for (final child in raw) {
        if (child is! Map) {
          warnings?.add('A filter child that is not an object was skipped.');
          continue;
        }
        try {
          children.add(
            Filter.fromJson(
              child.cast<String, Object?>(),
              warnings: warnings,
            ),
          );
        } on FormatException catch (e) {
          warnings?.add('A filter was skipped: ${e.message}');
        }
      }
    }
    return FilterGroup(
      children,
      join: json['join'] == 'or' ? FilterJoin.or : FilterJoin.and,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! FilterGroup) return false;
    if (other.join != join || other.children.length != children.length) {
      return false;
    }
    for (var i = 0; i < children.length; i++) {
      if (other.children[i] != children[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(join, Object.hashAll(children));

  @override
  String toString() => '(${children.join(' ${join.name.toUpperCase()} ')})';
}

const Object _unset = Object();

// -- Compiled filters --------------------------------------------------------
//
// A filter is written once by the user and then run over every row, so every
// decision that depends only on the filter belongs here rather than in the
// inner loop: folding the needle, coercing the operand to the column's type,
// and - the one that mattered most - turning an `isIn` list into a hash set.
// A checkbox filter list over a thousand values was O(rows x values).

/// A [Filter] prepared to be run over many rows.
///
/// Obtained from [Filter.compile]. Immutable and safe to keep for as long as
/// the filter and the column types stand.
abstract class CompiledFilter {
  const CompiledFilter();

  /// Whether a row satisfies the filter, reading values through [read].
  bool test(Object? Function(String field) read);

  /// Whether this filter lets every row through, so a caller can skip it.
  bool get isPassThrough => false;
}

class _AlwaysTrue extends CompiledFilter {
  const _AlwaysTrue();

  @override
  bool test(Object? Function(String field) read) => true;

  @override
  bool get isPassThrough => true;
}

class _CompiledAnd extends CompiledFilter {
  _CompiledAnd(this.children);

  final List<CompiledFilter> children;

  @override
  bool test(Object? Function(String field) read) {
    for (var i = 0; i < children.length; i++) {
      if (!children[i].test(read)) return false;
    }
    return true;
  }
}

class _CompiledOr extends CompiledFilter {
  _CompiledOr(this.children);

  final List<CompiledFilter> children;

  @override
  bool test(Object? Function(String field) read) {
    for (var i = 0; i < children.length; i++) {
      if (children[i].test(read)) return true;
    }
    return false;
  }
}

class _CompiledPredicate extends CompiledFilter {
  _CompiledPredicate(this.field, this.predicate);

  final String field;
  final bool Function(Object? actual) predicate;

  @override
  bool test(Object? Function(String field) read) => predicate(read(field));
}

/// Compiles one condition, coercing its operands to [type] when it is known.
///
/// Exposed for a data source that compiles conditions itself; most callers
/// want [Filter.compile].
CompiledFilter compileCondition(FilterCondition condition, ColumnType? type) {
  if (condition.isEmpty) return const _AlwaysTrue();
  final field = condition.field;
  final folded = !condition.caseSensitive;
  final dateOnly = condition.dateOnly;

  Object? coerce(Object? operand) =>
      coerceFilterOperand(operand, type, dateOnly: dateOnly);

  int compare(Object? a, Object? b) {
    if (dateOnly && (a is DateTime || b is DateTime)) {
      return compareValues(_dateOnly(a), _dateOnly(b));
    }
    return folded ? compareValuesFolded(a, b) : compareValues(a, b);
  }

  Object? normalise(Object? value) =>
      dateOnly && value is DateTime ? _dateOnly(value) : value;

  final operand = coerce(condition.value);
  final second = coerce(condition.secondValue);

  switch (condition.operator) {
    case FilterOperator.equals:
      return _CompiledPredicate(field, (a) => compare(a, operand) == 0);
    case FilterOperator.notEquals:
      return _CompiledPredicate(field, (a) => compare(a, operand) != 0);
    case FilterOperator.contains:
      final needle = _textOf(operand, folded);
      return _CompiledPredicate(
        field,
        (a) => _textOf(a, folded).contains(needle),
      );
    case FilterOperator.notContains:
      final needle = _textOf(operand, folded);
      return _CompiledPredicate(
        field,
        (a) => !_textOf(a, folded).contains(needle),
      );
    case FilterOperator.startsWith:
      final needle = _textOf(operand, folded);
      return _CompiledPredicate(
        field,
        (a) => _textOf(a, folded).startsWith(needle),
      );
    case FilterOperator.endsWith:
      final needle = _textOf(operand, folded);
      return _CompiledPredicate(
        field,
        (a) => _textOf(a, folded).endsWith(needle),
      );
    case FilterOperator.greaterThan:
      return _CompiledPredicate(
        field,
        (a) => a != null && compare(a, operand) > 0,
      );
    case FilterOperator.greaterOrEqual:
      return _CompiledPredicate(
        field,
        (a) => a != null && compare(a, operand) >= 0,
      );
    case FilterOperator.lessThan:
      return _CompiledPredicate(
        field,
        (a) => a != null && compare(a, operand) < 0,
      );
    case FilterOperator.lessOrEqual:
      return _CompiledPredicate(
        field,
        (a) => a != null && compare(a, operand) <= 0,
      );
    case FilterOperator.between:
      // Bounds typed backwards still describe the same range.
      final ordered = compare(operand, second) <= 0;
      final low = ordered ? operand : second;
      final high = ordered ? second : operand;
      return _CompiledPredicate(
        field,
        (a) => a != null && compare(a, low) >= 0 && compare(a, high) <= 0,
      );
    case FilterOperator.isIn:
      final raw = condition.value;
      if (raw is! Iterable) return const _AlwaysTrue();
      // The whole point of compiling: one hash lookup per row instead of a
      // walk over every selected value.
      final keys = HashSet<Object?>();
      for (final value in raw) {
        keys.add(_setKey(normalise(coerce(value)), folded));
      }
      return _CompiledPredicate(
        field,
        (a) => keys.contains(_setKey(normalise(a), folded)),
      );
    case FilterOperator.isNull:
      return _CompiledPredicate(field, (a) => a == null);
    case FilterOperator.isNotNull:
      return _CompiledPredicate(field, (a) => a != null);
    case FilterOperator.isEmpty:
      return _CompiledPredicate(
        field,
        (a) => a == null || _textOf(a, false).isEmpty,
      );
    case FilterOperator.isNotEmpty:
      return _CompiledPredicate(
        field,
        (a) => a != null && _textOf(a, false).isNotEmpty,
      );
  }
}

DateTime? _dateOnly(Object? value) =>
    value is DateTime ? DateTime(value.year, value.month, value.day) : null;

String _textOf(Object? value, bool folded) {
  final text = value == null ? '' : '$value';
  return folded ? foldText(text) : text;
}

/// A hash key under which two values that a filter calls equal are the same.
///
/// `5` and `5.0` are one value, `'Apple'` and `'apple'` are one value when
/// the filter folds case, and a [DateTime] keys on its instant.
Object? _setKey(Object? value, bool folded) {
  if (value == null) return null;
  if (value is String) return folded ? foldText(value) : value;
  if (value is num) return value.toDouble();
  if (value is BigInt) return value.toDouble();
  if (value is DateTime) return value.microsecondsSinceEpoch;
  if (value is bool) return value;
  return '$value';
}

/// Coerces a filter operand to the type of the column it tests.
///
/// A filter row hands back whatever the user typed, so a number column's
/// filter arrived holding `'50'` and compared as text - `'100' < '50'`. A
/// date restored from a saved view written by an older build arrives as an
/// ISO string for the same reason. Anything that cannot be read as [type] is
/// returned unchanged, so a text column is never second-guessed.
Object? coerceFilterOperand(
  Object? operand,
  ColumnType? type, {
  bool dateOnly = false,
}) {
  if (operand == null || type == null) return operand;
  switch (type) {
    case ColumnType.number:
      if (operand is num || operand is BigInt) return operand;
      if (operand is String) {
        final parsed = num.tryParse(operand.trim());
        return parsed ?? operand;
      }
      return operand;
    case ColumnType.date:
      if (operand is DateTime) {
        return dateOnly ? _dateOnly(operand) : operand;
      }
      if (operand is String) {
        final parsed = DateTime.tryParse(operand.trim());
        if (parsed == null) return operand;
        return dateOnly ? _dateOnly(parsed) : parsed;
      }
      return operand;
    case ColumnType.boolean:
      if (operand is bool) return operand;
      if (operand is String) {
        final lower = operand.trim().toLowerCase();
        if (lower == 'true') return true;
        if (lower == 'false') return false;
      }
      return operand;
    case ColumnType.text:
    case ColumnType.custom:
      return operand;
  }
}

/// Key a typed operand is written under in JSON.
const String filterDateKey = r'$date';

/// Key a [BigInt] operand is written under in JSON.
const String filterBigIntKey = r'$bigint';

/// Encodes a filter operand as something `jsonEncode` accepts.
///
/// A [DateTime] made `jsonEncode` throw outright, which meant a saved view
/// holding a date filter could not be stored at all.
Object? encodeFilterOperand(Object? operand) {
  if (operand is DateTime) {
    return {filterDateKey: operand.toIso8601String()};
  }
  if (operand is BigInt) return {filterBigIntKey: operand.toString()};
  if (operand is Iterable) {
    return [for (final value in operand) encodeFilterOperand(value)];
  }
  return operand;
}

/// Decodes what [encodeFilterOperand] wrote.
///
/// A bare ISO string is left as a string: it may be a text column's operand,
/// and a date column's operand is coerced by [coerceFilterOperand] against
/// the column type, which knows which it is.
Object? decodeFilterOperand(Object? operand) {
  if (operand is Map) {
    final date = operand[filterDateKey];
    if (date is String) {
      return DateTime.tryParse(date) ?? date;
    }
    final big = operand[filterBigIntKey];
    if (big is String) {
      return BigInt.tryParse(big) ?? big;
    }
    return operand;
  }
  if (operand is List) {
    return [for (final value in operand) decodeFilterOperand(value)];
  }
  return operand;
}
