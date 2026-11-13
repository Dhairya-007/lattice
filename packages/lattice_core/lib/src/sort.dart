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
        direction: isAscending ? SortDirection.descending : SortDirection.ascending,
        nulls: nulls,
      );

  Map<String, Object?> toJson() => {
        'field': field,
        'dir': direction.name,
        if (nulls != NullsPosition.last) 'nulls': nulls.name,
      };

  static SortSpec fromJson(Map<String, Object?> json) => SortSpec(
        json['field']! as String,
        direction: json['dir'] == 'descending'
            ? SortDirection.descending
            : SortDirection.ascending,
        nulls: json['nulls'] == 'first' ? NullsPosition.first : NullsPosition.last,
      );

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
      final va = column.value(a);
      final vb = column.value(b);
      if (va == null || vb == null) {
        if (va == null && vb == null) continue;
        final nullFirst = sort.nulls == NullsPosition.first;
        // Null placement is absolute: it does not flip with the direction.
        return (va == null) == nullFirst ? -1 : 1;
      }
      final cmp = column.comparator?.call(va, vb) ?? compareValues(va, vb);
      if (cmp != 0) return sort.isAscending ? cmp : -cmp;
    }
    return 0;
  };
}

/// Returns a new list of [rows] ordered by [sorts], preserving the original
/// order of rows that compare equal.
List<T> sortRows<T>(
  List<T> rows,
  List<SortSpec> sorts,
  Map<String, GridColumn<T>> columns,
) {
  if (sorts.isEmpty || rows.length < 2) return List<T>.of(rows);
  final compare = buildComparator<T>(sorts, columns);
  final decorated = List<(int, T)>.generate(
    rows.length,
    (i) => (i, rows[i]),
    growable: false,
  );
  decorated.sort((x, y) {
    final cmp = compare(x.$2, y.$2);
    return cmp != 0 ? cmp : x.$1.compareTo(y.$1);
  });
  return [for (final d in decorated) d.$2];
}

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
