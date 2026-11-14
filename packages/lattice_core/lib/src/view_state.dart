/// A saved view: how the user arranged the grid, as plain JSON.
library;

import 'column.dart';
import 'filter.dart';
import 'group.dart';
import 'layout.dart';
import 'schema.dart';
import 'sort.dart';

/// One column's arrangement.
class ColumnViewState {
  const ColumnViewState({
    required this.field,
    this.width,
    this.visible = true,
    this.pin = ColumnPin.none,
  });

  /// Which column this describes.
  final String field;

  /// The user's resized width, or null if they never dragged it.
  ///
  /// Null rather than the column's declared width on purpose: a saved view
  /// that records a width the user never chose would pin the layout to
  /// whatever the default was on the day they saved it.
  final double? width;

  final bool visible;
  final ColumnPin pin;

  /// Position in the column list is carried by the order of
  /// [GridViewState.columns], not by an index here, so a view restored onto a
  /// grid whose columns have changed cannot leave two columns claiming the
  /// same slot.
  Map<String, Object?> toJson() => {
        'field': field,
        if (width != null) 'width': width,
        if (!visible) 'visible': false,
        if (pin != ColumnPin.none) 'pin': pin.name,
      };

  static ColumnViewState fromJson(Map<String, Object?> json) {
    return ColumnViewState(
      field: json['field']! as String,
      width: (json['width'] as num?)?.toDouble(),
      visible: json['visible'] != false,
      pin: ColumnPin.values.firstWhere(
        (p) => p.name == json['pin'],
        orElse: () => ColumnPin.none,
      ),
    );
  }

  @override
  String toString() => 'ColumnViewState($field)';
}

/// Everything about how a grid is arranged, in a form that round-trips
/// through storage or an HTTP backend.
///
/// "Remember my layout" is one of the first things a user asks of a grid, and
/// it needs more than the query: the widths they dragged, the order they
/// moved columns into, what they hid and what they pinned. Those live in the
/// controller and were not serialised anywhere.
///
/// What a view cannot carry is functions. Aggregations, a column's accessors
/// and a [GroupSpec]'s `keyOf`/`labelOf` are code, so they stay with the
/// column and group definitions the grid is built from; restoring a view
/// re-applies the saved group fields to the specs you supply. See
/// `GridController.restoreState`.
class GridViewState {
  const GridViewState({
    this.sorts = const [],
    this.filter,
    this.columnFilters = const {},
    this.search = '',
    this.groups = const [],
    this.collapsedGroupPaths = const [],
    this.columns = const [],
    this.pageIndex = 0,
    this.pageSize,
    this.frozenRowCount = 0,
    this.frozenRowCountBottom = 0,
    this.columnFit = ColumnFit.none,
  });

  final List<SortSpec> sorts;

  /// The structured filter set alongside the filter row, if any.
  final Filter? filter;

  /// Filter-row conditions, keyed by field.
  final Map<String, FilterCondition> columnFilters;

  final String search;
  final List<GroupSpec> groups;

  /// Group paths whose expansion differs from the grid's default.
  ///
  /// Named for what it usually means - the groups the user closed - but it is
  /// the override set, so on a grid built with `groupsExpandedByDefault:
  /// false` these are the groups they opened.
  final List<String> collapsedGroupPaths;

  /// Column arrangement, in the order the columns should appear.
  final List<ColumnViewState> columns;

  final int pageIndex;
  final int? pageSize;
  final int frozenRowCount;
  final int frozenRowCountBottom;
  final ColumnFit columnFit;

  /// JSON for storage, stamped with [latticeSchemaVersion].
  Map<String, Object?> toJson() => {
        latticeSchemaVersionKey: latticeSchemaVersion,
        if (sorts.isNotEmpty) 'sorts': [for (final s in sorts) s.toJson()],
        if (filter != null) 'filter': filter!.toJson(),
        if (columnFilters.isNotEmpty)
          'columnFilters': {
            for (final entry in columnFilters.entries)
              entry.key: entry.value.toJson(),
          },
        if (search.isNotEmpty) 'search': search,
        if (groups.isNotEmpty) 'groups': [for (final g in groups) g.toJson()],
        if (collapsedGroupPaths.isNotEmpty) 'collapsed': collapsedGroupPaths,
        if (columns.isNotEmpty)
          'columns': [for (final c in columns) c.toJson()],
        if (pageIndex != 0) 'pageIndex': pageIndex,
        if (pageSize != null) 'pageSize': pageSize,
        if (frozenRowCount != 0) 'frozenRows': frozenRowCount,
        if (frozenRowCountBottom != 0) 'frozenRowsBottom': frozenRowCountBottom,
        if (columnFit != ColumnFit.none) 'fit': columnFit.name,
      };

  /// Rebuilds a view produced by [toJson].
  ///
  /// Unknown fields are ignored and missing ones take their defaults, so a
  /// view saved by an older version of an app still restores what it can
  /// rather than throwing.
  static GridViewState fromJson(Map<String, Object?> json) {
    requireSupportedSchema(json, what: 'This saved view');
    final filters = json['columnFilters'];
    return GridViewState(
      sorts: [
        for (final s in (json['sorts'] as List? ?? const []))
          SortSpec.fromJson((s as Map).cast<String, Object?>()),
      ],
      filter: json['filter'] == null
          ? null
          : Filter.fromJson((json['filter']! as Map).cast<String, Object?>()),
      columnFilters: filters is Map
          ? {
              for (final entry in filters.entries)
                '${entry.key}': FilterCondition.fromJson(
                  (entry.value as Map).cast<String, Object?>(),
                ),
            }
          : const {},
      search: json['search'] as String? ?? '',
      groups: [
        for (final g in (json['groups'] as List? ?? const []))
          GroupSpec.fromJson((g as Map).cast<String, Object?>()),
      ],
      collapsedGroupPaths: [
        for (final p in (json['collapsed'] as List? ?? const [])) '$p',
      ],
      columns: [
        for (final c in (json['columns'] as List? ?? const []))
          ColumnViewState.fromJson((c as Map).cast<String, Object?>()),
      ],
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      pageSize: (json['pageSize'] as num?)?.toInt(),
      frozenRowCount: (json['frozenRows'] as num?)?.toInt() ?? 0,
      frozenRowCountBottom: (json['frozenRowsBottom'] as num?)?.toInt() ?? 0,
      columnFit: ColumnFit.values.firstWhere(
        (f) => f.name == json['fit'],
        orElse: () => ColumnFit.none,
      ),
    );
  }

  @override
  String toString() => 'GridViewState(${toJson()})';
}
