/// Row grouping: tree construction, aggregates and flattening for display.
library;

import 'aggregate.dart';
import 'column.dart';
import 'compare.dart';
import 'sort.dart';

/// One level of grouping.
class GroupSpec {
  const GroupSpec(
    this.field, {
    this.direction = SortDirection.ascending,
    this.nulls = NullsPosition.last,
    this.keyOf,
    this.labelOf,
    this.blankLabel = '(blank)',
  });

  final String field;

  /// Order of the group headers themselves.
  final SortDirection direction;

  /// Where the blank group lands relative to the rest.
  ///
  /// Absolute, as it is for sorting: reversing the header order used to flip
  /// the blank group to the top, which reads as "the empty ones matter most"
  /// rather than as the same group seen the other way round.
  final NullsPosition nulls;

  /// Buckets a raw value into a group key, for grouping by something coarser
  /// than the stored value (a date's month, a number's decade).
  final Object? Function(Object? value)? keyOf;

  /// Renders a group key as a header label.
  final String Function(Object? key)? labelOf;

  /// Label for the group of rows whose value is null.
  ///
  /// The engine owns exactly one piece of user-visible text, and this is it.
  /// It is a field rather than a lookup because `lattice_core` must not grow
  /// a dependency on anyone's localisations: an app that needs it translated
  /// passes the translated string, from wherever its other strings come
  /// from. [labelOf], where given, overrides this as it does everything else.
  final String blankLabel;

  Object? keyFor(Object? value) => keyOf != null ? keyOf!(value) : value;

  String labelFor(Object? key) =>
      labelOf != null ? labelOf!(key) : (key == null ? blankLabel : '$key');

  /// A stable string identifying which buckets this spec produces, for use as
  /// a cache key.
  ///
  /// [keyOf] and [labelOf] are part of it: regrouping the same field with a
  /// different bucketing function has to rebuild the groups, and a key of
  /// `field:direction` alone silently served the previous buckets.
  ///
  /// Those two are compared by closure identity, which is all Dart offers for
  /// a function. Two closures written at the same place are *not* equal in
  /// general - a fresh closure is created each time the expression runs - so
  /// a spec built inline on every rebuild misses this cache every time. Hoist
  /// the bucketing function to a static or top-level function, or keep it in
  /// a field, and the spec compares equal across rebuilds.
  String get fingerprint => '$field:${direction.name}:${nulls.name}'
      ':${keyOf?.hashCode ?? 0}:${labelOf?.hashCode ?? 0}:$blankLabel';

  /// JSON for a saved view.
  ///
  /// [keyOf] and [labelOf] are functions and cannot be serialised; pass them
  /// again through [restore] when rebuilding a spec from storage.
  Map<String, Object?> toJson() => {
        'field': field,
        'dir': direction.name,
        if (nulls != NullsPosition.last) 'nulls': nulls.name,
      };

  /// Rebuilds a spec produced by [toJson].
  ///
  /// Throws a [FormatException] rather than a [TypeError] for a document
  /// without a usable field, so one corrupt entry in a saved view can be
  /// reported instead of crashing the restore.
  static GroupSpec fromJson(Map<String, Object?> json) {
    final field = json['field'];
    if (field is! String || field.isEmpty) {
      throw FormatException('A group needs a non-empty "field"', json);
    }
    return GroupSpec(
      field,
      direction: json['dir'] == 'descending'
          ? SortDirection.descending
          : SortDirection.ascending,
      nulls:
          json['nulls'] == 'first' ? NullsPosition.first : NullsPosition.last,
    );
  }

  /// This spec with the bucketing functions supplied, for restoring a saved
  /// view whose JSON could not carry them.
  GroupSpec restore({
    Object? Function(Object? value)? keyOf,
    String Function(Object? key)? labelOf,
    String? blankLabel,
  }) {
    return GroupSpec(
      field,
      direction: direction,
      nulls: nulls,
      keyOf: keyOf ?? this.keyOf,
      labelOf: labelOf ?? this.labelOf,
      blankLabel: blankLabel ?? this.blankLabel,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GroupSpec &&
      other.field == field &&
      other.direction == direction &&
      other.nulls == nulls &&
      other.keyOf == keyOf &&
      other.labelOf == labelOf &&
      other.blankLabel == blankLabel;

  @override
  int get hashCode =>
      Object.hash(field, direction, nulls, keyOf, labelOf, blankLabel);

  @override
  String toString() => 'group by $field';
}

/// One level of a group's identity: which column, and which value.
///
/// A group's full key path is what a server needs to answer "give me the rows
/// in this group": the path string identifies a group to the grid, but only
/// the field/value pairs translate into a filter.
class GroupKey {
  const GroupKey(this.field, this.key);

  final String field;
  final Object? key;

  @override
  bool operator ==(Object other) =>
      other is GroupKey && other.field == field && other.key == key;

  @override
  int get hashCode => Object.hash(field, key);

  @override
  String toString() => '$field=$key';
}

/// A node of the grouped row tree.
class GroupNode<T> {
  GroupNode({
    required this.field,
    required this.key,
    required this.label,
    required this.depth,
    required this.path,
    this.children = const [],
    this.rows = const [],
    this.aggregates = const AggregateResult.empty(),
    this.keys = const [],
    this.declaredCount,
    this.loaded = true,
  });

  final String field;
  final Object? key;
  final String label;

  /// Zero-based nesting level.
  final int depth;

  /// Stable identity of this group across rebuilds, built from the keys of
  /// every ancestor. Used to remember expansion state.
  ///
  /// The local grouper builds these with [groupPathSegment], which tags the
  /// field and the key's type so that two different groups cannot share one
  /// path. A source that groups server-side chooses its own paths and only
  /// has to keep them stable and distinct; using [groupPathSegment] makes
  /// them match what a local grid would produce.
  final String path;

  /// Child groups, when more grouping levels remain.
  final List<GroupNode<T>> children;

  /// Leaf rows, when this is the innermost level.
  final List<T> rows;

  final AggregateResult aggregates;

  /// This group's identity, from the outermost level inwards.
  ///
  /// What a source is given when the grid asks it for this group's contents.
  final List<GroupKey> keys;

  /// How many rows this group holds, when the grid cannot count them.
  ///
  /// A source that groups server-side returns a header and a count without
  /// the rows, so the count has to be stated rather than derived. Null means
  /// "count what is here".
  final int? declaredCount;

  /// Whether this group's contents are in hand.
  ///
  /// False for a header a source returned without its rows; the grid asks for
  /// them when the group is opened. See
  /// [LatticeDataSource.fetchGroupChildren].
  final bool loaded;

  bool get isLeafGroup => children.isEmpty;

  /// Number of data rows anywhere beneath this node.
  int get rowCount =>
      declaredCount ??
      (isLeafGroup
          ? rows.length
          : children.fold(0, (sum, child) => sum + child.rowCount));

  /// This node with its contents filled in, as a lazy load provides them.
  GroupNode<T> withContents({
    List<GroupNode<T>> children = const [],
    List<T> rows = const [],
    AggregateResult? aggregates,
  }) {
    return GroupNode<T>(
      field: field,
      key: key,
      label: label,
      depth: depth,
      path: path,
      children: children,
      rows: rows,
      aggregates: aggregates ?? this.aggregates,
      keys: keys,
      declaredCount: declaredCount,
    );
  }

  /// This node with its children replaced, keeping everything else.
  GroupNode<T> withChildren(List<GroupNode<T>> children) {
    return GroupNode<T>(
      field: field,
      key: key,
      label: label,
      depth: depth,
      path: path,
      children: children,
      rows: rows,
      aggregates: aggregates,
      keys: keys,
      declaredCount: declaredCount,
      loaded: loaded,
    );
  }

  /// Every data row beneath this node, in display order.
  List<T> get allRows =>
      isLeafGroup ? rows : [for (final c in children) ...c.allRows];

  /// This node with [transform] applied to every row beneath it.
  ///
  /// Used to show an optimistic edit inside a grouped view: the pending value
  /// has to be substituted before the tree is flattened, or the rows the user
  /// sees are the ones the source last sent.
  GroupNode<T> mapRows(T Function(T row) transform) {
    return GroupNode<T>(
      field: field,
      key: key,
      label: label,
      depth: depth,
      path: path,
      children: [for (final child in children) child.mapRows(transform)],
      rows: [for (final row in rows) transform(row)],
      aggregates: aggregates,
      keys: keys,
      declaredCount: declaredCount,
      loaded: loaded,
    );
  }
}

/// Groups [rows] by [groups], computing [aggregations] at every level.
///
/// Rows arrive already sorted and filtered; grouping preserves their relative
/// order inside each bucket.
List<GroupNode<T>> buildGroups<T>(
  List<T> rows,
  List<GroupSpec> groups,
  Map<String, GridColumn<T>> columns, {
  List<Aggregation> aggregations = const [],
  int depth = 0,
  String parentPath = '',
  List<GroupKey> parentKeys = const [],
}) {
  if (groups.isEmpty || rows.isEmpty) return const [];
  final spec = groups.first;
  final column = columns[spec.field];
  final buckets = <Object?, List<T>>{};
  final labels = <Object?, String>{};
  for (final row in rows) {
    final raw = column == null ? null : column.value(row);
    final key = spec.keyFor(raw);
    buckets.putIfAbsent(key, () => <T>[]).add(row);
    labels[key] ??= spec.labelFor(key);
  }

  // Header order follows the column's own comparator, so that groups sort
  // the way the column sorts: a priority column ordering High/Medium/Low by
  // comparator used to produce headers in alphabetical order. A keyOf
  // bucketing function makes the keys something the column's comparator has
  // never seen, so that case keeps the generic order.
  final compare = spec.keyOf == null
      ? (column?.comparator ??
          defaultCompareFor(column?.type ?? ColumnType.text))
      : compareValues;
  final nullsFirst = spec.nulls == NullsPosition.first;
  final keys = buckets.keys.toList()
    ..sort((a, b) {
      // Nulls are placed before the direction is applied, so the blank group
      // does not jump to the top when the headers are reversed.
      if (a == null || b == null) {
        if (a == null && b == null) return 0;
        return (a == null) == nullsFirst ? -1 : 1;
      }
      final cmp = compare(a, b);
      return spec.direction == SortDirection.ascending ? cmp : -cmp;
    });

  final rest = groups.sublist(1);
  return [
    for (final key in keys)
      () {
        final bucket = buckets[key]!;
        final segment = groupPathSegment(spec.field, key);
        final path = parentPath.isEmpty ? segment : '$parentPath\u001f$segment';
        final keys = [...parentKeys, GroupKey(spec.field, key)];
        final children = buildGroups<T>(
          bucket,
          rest,
          columns,
          aggregations: aggregations,
          depth: depth + 1,
          parentPath: path,
          parentKeys: keys,
        );
        return GroupNode<T>(
          field: spec.field,
          key: key,
          label: labels[key]!,
          depth: depth,
          path: path,
          keys: keys,
          children: children,
          rows: children.isEmpty ? bucket : const [],
          aggregates: computeAggregates<T>(
            bucket,
            aggregations,
            (row, field) => columns[field]?.value(row),
          ),
        );
      }(),
  ];
}

/// One segment of a [GroupNode.path].
///
/// The field and the key's type are both part of it. A path of bare keys
/// collided in two ways that a user could reach from the UI: a `null` group
/// and a group whose value is the string `"null"` produced the same path, as
/// did `1` and `"1"`, so two different groups shared one expansion state and
/// one lazy-load cache entry; and regrouping by another field reused the
/// previous field's collapsed paths, so a freshly grouped column could open
/// with arbitrary groups already closed.
String groupPathSegment(String field, Object? key) =>
    '${_escapePathPart(field)}=${pathKeySegment(key)}';

/// One key, encoded with its type so that two keys of different types cannot
/// produce the same path.
///
/// Shared with tree paths, which have the same collision to avoid.
String pathKeySegment(Object? key) =>
    '${_tagOf(key)}:${_escapePathPart(_keyText(key))}';

String _tagOf(Object? key) {
  if (key == null) return 'n';
  if (key is String) return 's';
  if (key is int) return 'i';
  if (key is double) return 'f';
  if (key is bool) return 'b';
  if (key is DateTime) return 't';
  if (key is BigInt) return 'g';
  return 'o';
}

String _keyText(Object? key) {
  if (key == null) return '';
  if (key is DateTime) return key.toIso8601String();
  return '$key';
}

/// Escapes the separators a path is built from, so that a key containing one
/// cannot forge a segment boundary.
String _escapePathPart(String text) => text
    .replaceAll('\u001e', '\u001e\u001e')
    .replaceAll('\u001f', '\u001e1')
    .replaceAll('=', '\u001e2');
