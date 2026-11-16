/// Multi-column sorting.
library;

import 'column.dart';
import 'compare.dart';

enum SortDirection { ascending, descending }

/// Where nulls land relative to real values.
enum NullsPosition { first, last }

/// One level of an ordering.
class SortSpec {
  const SortSpec(
    this.field, {
    this.direction = SortDirection.ascending,
    this.nulls = NullsPosition.last,
  });

  final String field;
  final SortDirection direction;
  final NullsPosition nulls;

  bool get isAscending => direction == SortDirection.ascending;

  /// The same field sorted the other way.
  SortSpec get reversed => SortSpec(
        field,
        direction:
            isAscending ? SortDirection.descending : SortDirection.ascending,
        nulls: nulls,
      );

  /// A stable string identifying the ordering this spec asks for, for use as
  /// a cache key.
  ///
  /// Every field that changes the result appears in it. A cache key assembled
  /// by its caller is a key that forgets a field the next time one is added;
  /// a spec states its own identity instead.
  String get fingerprint => '$field:${direction.name}:${nulls.name}';

  Map<String, Object?> toJson() => {
        'field': field,
        'dir': direction.name,
        if (nulls != NullsPosition.last) 'nulls': nulls.name,
      };

  /// Rebuilds a spec produced by [toJson].
  ///
  /// Throws a [FormatException] - not a [TypeError] - when `field` is missing
  /// or is not a string, so that a caller restoring a saved view can report a
  /// corrupt document instead of crashing on a null check.
  static SortSpec fromJson(Map<String, Object?> json) {
    final field = json['field'];
    if (field is! String || field.isEmpty) {
      throw FormatException('A sort needs a non-empty "field"', json);
    }
    return SortSpec(
      field,
      direction: json['dir'] == 'descending'
          ? SortDirection.descending
          : SortDirection.ascending,
      nulls:
          json['nulls'] == 'first' ? NullsPosition.first : NullsPosition.last,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SortSpec &&
      other.field == field &&
      other.direction == direction &&
      other.nulls == nulls;

  @override
  int get hashCode => Object.hash(field, direction, nulls);

  @override
  String toString() => '$field ${isAscending ? 'asc' : 'desc'}';
}

/// Builds a [Comparator] for `T` that applies [sorts] in order, using each
/// column's own [GridColumn.comparator] where one is defined.
///
/// The returned comparator is stable with respect to the input order: rows the
/// sort cannot distinguish keep their relative positions, because
/// [sortRows] sorts an index-decorated copy.
Comparator<T> buildComparator<T>(
  List<SortSpec> sorts,
  Map<String, GridColumn<T>> columns,
) {
  return (T a, T b) {
    for (final sort in sorts) {
      final column = columns[sort.field];
      if (column == null) continue;
      final va = column.sortValue(a);
      final vb = column.sortValue(b);
      if (va == null || vb == null) {
        if (va == null && vb == null) continue;
        final nullFirst = sort.nulls == NullsPosition.first;
        // Null placement is absolute: it does not flip with the direction.
        return (va == null) == nullFirst ? -1 : 1;
      }
      final cmp = column.comparator?.call(va, vb) ??
          defaultCompareFor(column.type)(va, vb);
      if (cmp != 0) return sort.isAscending ? cmp : -cmp;
    }
    return 0;
  };
}

/// The comparison a column of [type] orders by when it declares no
/// [GridColumn.comparator] of its own.
///
/// Text folds case and accents away, with the exact comparison as a tiebreak,
/// because a user sorting a name column does not expect `Cherry` above
/// `apple`: code-unit order puts every capital first and every accent after
/// `z`. Every other type keeps the natural order of its values.
Comparator<Object?> defaultCompareFor(ColumnType type) =>
    type == ColumnType.text ? compareValuesCaseInsensitive : compareValues;

/// Returns a new list of [rows] ordered by [sorts], preserving the original
/// order of rows that compare equal.
List<T> sortRows<T>(
  List<T> rows,
  List<SortSpec> sorts,
  Map<String, GridColumn<T>> columns,
) {
  if (sorts.isEmpty || rows.length < 2) return List<T>.of(rows);

  // Read every sort key once per row rather than on every comparison. A
  // comparison sort makes O(n log n) comparisons, so calling the accessors
  // inside the comparator reads each row's value ~log n times - about 16x
  // over at 50k rows, and more when the accessor computes something.
  final levels = [
    for (final sort in sorts)
      if (columns[sort.field] != null) sort,
  ];
  if (levels.isEmpty) return List<T>.of(rows);

  final count = rows.length;
  final depth = levels.length;
  final keys = List<Object?>.filled(count * depth, null);
  for (var level = 0; level < depth; level++) {
    final read = columns[levels[level].field]!.sortValue;
    final base = level * count;
    for (var i = 0; i < count; i++) {
      keys[base + i] = read(rows[i]);
    }
  }

  final comparators = [
    for (final level in levels) columns[level.field]!.comparator,
  ];
  final ascending = [for (final level in levels) level.isAscending];
  final nullsFirst = [
    for (final level in levels) level.nulls == NullsPosition.first,
  ];

  // Two orderings cost more per comparison than they need to, and both can
  // be answered by a key computed once per row: a case- and accent-folded
  // text order, and a natural one. The raw key stays for the exact tiebreak
  // that keeps the order total.
  final folded = List<List<String>?>.filled(depth, null);
  final comparatorForLevel = List<Comparator<Object?>?>.of(comparators);
  // Levels whose key turned out to equal the value itself, so the plain
  // string comparison already gives the order the key would have.
  final plainString = List<bool>.filled(depth, false);
  for (var level = 0; level < depth; level++) {
    final column = columns[levels[level].field]!;
    final comparator = comparators[level];
    final natural = comparator == compareValuesNatural;
    if (comparator != null && !natural) continue;
    if (!natural && column.type != ColumnType.text) continue;
    final base = level * count;
    if (_keyKind(keys, base, count) != _kindString) continue;
    final keysForLevel = List<String>.filled(count, '');
    // A column that is already lower case and unaccented folds to itself, and
    // then the folded comparison is pure overhead: two string compares where
    // one would do, on a column where ties are common. Detecting that keeps
    // the folded default as cheap as the code-unit order it replaced.
    var changed = false;
    for (var i = 0; i < count; i++) {
      final value = keys[base + i];
      if (value == null) continue;
      final raw = value as String;
      final key = natural ? naturalSortKey(raw) : foldText(raw);
      keysForLevel[i] = key;
      if (!changed && key != raw) changed = true;
    }
    // The key answers what the comparator was for.
    if (natural) comparatorForLevel[level] = null;
    if (changed) {
      folded[level] = keysForLevel;
    } else {
      // Every key came back identical to its value - a column that is
      // already lower case and unaccented, or has no digits to read as
      // numbers - so comparing the values directly is the same order for a
      // fraction of the work. This is what keeps a natural sort over
      // digit-free text, and the folded default over ordinary data, as cheap
      // as the plain comparison.
      plainString[level] = true;
    }
  }

  final order = List<int>.generate(count, (i) => i, growable: false);

  // One sort column is the overwhelmingly common case - it is what a header
  // click produces - so it gets a comparison with no type tests and no
  // closure indirection in the inner loop.
  if (depth == 1 && comparatorForLevel[0] == null) {
    final ascendingOnly = ascending[0];
    final nullsFirstOnly = nullsFirst[0];
    final kind = _keyKind(keys, 0, count);

    int? nullOrder(Object? va, Object? vb) {
      if (va == null && vb == null) return 0;
      if (va == null || vb == null) {
        return (va == null) == nullsFirstOnly ? -1 : 1;
      }
      return null;
    }

    final foldedOnly = folded[0];
    if (foldedOnly != null) {
      order.sort((a, b) {
        final va = keys[a];
        final vb = keys[b];
        final nulls = nullOrder(va, vb);
        if (nulls != null) return nulls == 0 ? a.compareTo(b) : nulls;
        var cmp = foldedOnly[a].compareTo(foldedOnly[b]);
        if (cmp == 0) cmp = (va! as String).compareTo(vb! as String);
        if (cmp != 0) return ascendingOnly ? cmp : -cmp;
        return a.compareTo(b);
      });
      return [for (final i in order) rows[i]];
    }
    if (kind == _kindNum) {
      order.sort((a, b) {
        final va = keys[a];
        final vb = keys[b];
        final nulls = nullOrder(va, vb);
        if (nulls != null) return nulls == 0 ? a.compareTo(b) : nulls;
        final cmp = (va! as num).compareTo(vb! as num);
        if (cmp != 0) return ascendingOnly ? cmp : -cmp;
        return a.compareTo(b);
      });
      return [for (final i in order) rows[i]];
    }
    if (kind == _kindString) {
      order.sort((a, b) {
        final va = keys[a];
        final vb = keys[b];
        final nulls = nullOrder(va, vb);
        if (nulls != null) return nulls == 0 ? a.compareTo(b) : nulls;
        final cmp = (va! as String).compareTo(vb! as String);
        if (cmp != 0) return ascendingOnly ? cmp : -cmp;
        return a.compareTo(b);
      });
      return [for (final i in order) rows[i]];
    }
  }

  // Whether a level needs the folding comparison at comparison time, which
  // is only so when its values are text that folding changes and no key was
  // precomputed for it.
  final foldsAtCompare = [
    for (var level = 0; level < depth; level++)
      comparatorForLevel[level] == null &&
          !plainString[level] &&
          folded[level] == null &&
          columns[levels[level].field]!.type == ColumnType.text,
  ];

  order.sort((a, b) {
    for (var level = 0; level < depth; level++) {
      final base = level * count;
      final va = keys[base + a];
      final vb = keys[base + b];
      if (va == null || vb == null) {
        if (va == null && vb == null) continue;
        // Null placement is absolute: it does not flip with the direction.
        return (va == null) == nullsFirst[level] ? -1 : 1;
      }
      final foldedLevel = folded[level];
      var cmp = 0;
      // Explicit branches rather than a comparator read out of a list: a
      // tear-off called per comparison per level cost half as much again as
      // the direct call over 50k rows and three levels.
      if (foldedLevel != null) {
        cmp = foldedLevel[a].compareTo(foldedLevel[b]);
        if (cmp == 0) cmp = (va as String).compareTo(vb as String);
      } else {
        final comparator = comparatorForLevel[level];
        if (comparator != null) {
          cmp = comparator(va, vb);
        } else if (foldsAtCompare[level]) {
          cmp = compareValuesCaseInsensitive(va, vb);
        } else {
          cmp = compareValues(va, vb);
        }
      }
      if (cmp != 0) return ascending[level] ? cmp : -cmp;
    }
    // Fall back to the input position, which keeps the sort stable.
    return a.compareTo(b);
  });

  return [for (final i in order) rows[i]];
}

/// Whether every non-null key in a level is a number, or every one a string.
///
/// Settling the type once lets [sortRows] use a direct comparison for the
/// single-column case instead of [compareValues], which re-tests the operand
/// types on every one of the O(n log n) comparisons.
int _keyKind(List<Object?> keys, int base, int count) {
  var allNum = true;
  var allString = true;
  for (var i = 0; i < count; i++) {
    final value = keys[base + i];
    if (value == null) continue;
    if (value is! num) allNum = false;
    if (value is! String) allString = false;
    if (!allNum && !allString) return _kindOther;
  }
  if (allNum) return _kindNum;
  if (allString) return _kindString;
  return _kindOther;
}

const int _kindOther = 0;
const int _kindNum = 1;
const int _kindString = 2;

/// Applies the three-state header-click cycle
/// (unsorted -> ascending -> descending -> unsorted) to [sorts].
///
/// With [additive] false the clicked column replaces the whole ordering, which
/// is the plain-click behaviour; with it true the column is appended, which is
/// the ctrl/cmd-click behaviour for building a multi-level sort.
List<SortSpec> cycleSort(
  List<SortSpec> sorts,
  String field, {
  bool additive = false,
}) {
  final existing = sorts.firstWhere(
    (s) => s.field == field,
    orElse: () => const SortSpec('\u0000'),
  );
  final has = existing.field == field;
  if (!additive) {
    if (!has) return [SortSpec(field)];
    return existing.isAscending ? [existing.reversed] : const [];
  }
  final next = List<SortSpec>.of(sorts);
  if (!has) return next..add(SortSpec(field));
  final index = next.indexWhere((s) => s.field == field);
  if (existing.isAscending) {
    next[index] = existing.reversed;
  } else {
    next.removeAt(index);
  }
  return next;
}
