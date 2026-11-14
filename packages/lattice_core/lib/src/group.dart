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
    this.keyOf,
    this.labelOf,
  });

  final String field;

  /// Order of the group headers themselves.
  final SortDirection direction;

  /// Buckets a raw value into a group key, for grouping by something coarser
  /// than the stored value (a date's month, a number's decade).
  final Object? Function(Object? value)? keyOf;

  /// Renders a group key as a header label.
  final String Function(Object? key)? labelOf;

  Object? keyFor(Object? value) => keyOf != null ? keyOf!(value) : value;

  String labelFor(Object? key) =>
      labelOf != null ? labelOf!(key) : (key == null ? '(blank)' : '$key');

  /// A stable string identifying which buckets this spec produces, for use as
  /// a cache key.
  ///
  /// [keyOf] and [labelOf] are part of it: regrouping the same field with a
  /// different bucketing function has to rebuild the groups, and a key of
  /// `field:direction` alone silently served the previous buckets. Closures
  /// written at the same place with the same captured values are `==` in
  /// Dart, so a spec rebuilt on every frame still hits the cache.
  String get fingerprint => '$field:${direction.name}'
      ':${keyOf?.hashCode ?? 0}:${labelOf?.hashCode ?? 0}';

  /// JSON for a saved view.
  ///
  /// [keyOf] and [labelOf] are functions and cannot be serialised; pass them
  /// again through [restore] when rebuilding a spec from storage.
  Map<String, Object?> toJson() => {'field': field, 'dir': direction.name};

  /// Rebuilds a spec produced by [toJson].
  static GroupSpec fromJson(Map<String, Object?> json) => GroupSpec(
        json['field']! as String,
        direction: json['dir'] == 'descending'
            ? SortDirection.descending
            : SortDirection.ascending,
      );

  /// This spec with the bucketing functions supplied, for restoring a saved
  /// view whose JSON could not carry them.
  GroupSpec restore({
    Object? Function(Object? value)? keyOf,
    String Function(Object? key)? labelOf,
  }) {
    return GroupSpec(
      field,
      direction: direction,
      keyOf: keyOf ?? this.keyOf,
      labelOf: labelOf ?? this.labelOf,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GroupSpec &&
      other.field == field &&
      other.direction == direction &&
      other.keyOf == keyOf &&
      other.labelOf == labelOf;

  @override
  int get hashCode => Object.hash(field, direction, keyOf, labelOf);

  @override
  String toString() => 'group by $field';
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
  });

  final String field;
  final Object? key;
  final String label;

  /// Zero-based nesting level.
  final int depth;

  /// Stable identity of this group across rebuilds, built from the keys of
  /// every ancestor. Used to remember expansion state.
  final String path;

  /// Child groups, when more grouping levels remain.
  final List<GroupNode<T>> children;

  /// Leaf rows, when this is the innermost level.
  final List<T> rows;

  final AggregateResult aggregates;

  bool get isLeafGroup => children.isEmpty;

  /// Number of data rows anywhere beneath this node.
  int get rowCount => isLeafGroup
      ? rows.length
      : children.fold(0, (sum, child) => sum + child.rowCount);

  /// Every data row beneath this node, in display order.
  List<T> get allRows =>
      isLeafGroup ? rows : [for (final c in children) ...c.allRows];
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

  final keys = buckets.keys.toList()
    ..sort((a, b) {
      final cmp = compareValues(a, b);
      return spec.direction == SortDirection.ascending ? cmp : -cmp;
    });

  final rest = groups.sublist(1);
  return [
    for (final key in keys)
      () {
        final bucket = buckets[key]!;
        final path = parentPath.isEmpty ? '$key' : '$parentPath\u001f$key';
        final children = buildGroups<T>(
          bucket,
          rest,
          columns,
          aggregations: aggregations,
          depth: depth + 1,
          parentPath: path,
        );
        return GroupNode<T>(
          field: spec.field,
          key: key,
          label: labels[key]!,
          depth: depth,
          path: path,
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
