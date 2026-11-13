/// Ordering primitives shared by sorting, grouping and range filters.
library;

/// Compares two arbitrary cell values in a total, null-safe order.
///
/// Nulls sort last. Numbers, strings, [DateTime], [bool] and [Comparable]
/// values compare naturally; values of different or incomparable types fall
/// back to comparing their string forms so that ordering is never arbitrary
/// between rebuilds.
int compareValues(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is DateTime && b is DateTime) return a.compareTo(b);
  if (a is bool && b is bool) {
    if (a == b) return 0;
    return a ? 1 : -1;
  }
  if (a is Comparable && b is Comparable && a.runtimeType == b.runtimeType) {
    return a.compareTo(b);
  }
  return '$a'.compareTo('$b');
}

/// Case- and accent-insensitive variant of [compareValues] for text columns.
int compareValuesCaseInsensitive(Object? a, Object? b) {
  if (a is String && b is String) {
    final byFold = a.toLowerCase().compareTo(b.toLowerCase());
    // Fall back to the exact comparison so the order stays total.
    return byFold != 0 ? byFold : a.compareTo(b);
  }
  return compareValues(a, b);
}

/// Compares values the way a human reads embedded numbers, so that
/// `item2` sorts before `item10`.
int compareValuesNatural(Object? a, Object? b) {
  if (a is! String || b is! String) return compareValues(a, b);
  final chunks = RegExp(r'\d+|\D+');
  final left = chunks.allMatches(a).map((m) => m[0]!).toList();
  final right = chunks.allMatches(b).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final l = left[i];
    final r = right[i];
    final ln = int.tryParse(l);
    final rn = int.tryParse(r);
    final result = (ln != null && rn != null)
        ? ln.compareTo(rn)
        : l.toLowerCase().compareTo(r.toLowerCase());
    if (result != 0) return result;
  }
  return left.length.compareTo(right.length);
}
