/// The flat list of visual rows a UI adapter renders.
library;

import 'dart:collection';

import 'aggregate.dart';
import 'group.dart';

/// A single renderable row.
///
/// Grouping turns a tree into this flat list so that adapters can keep using a
/// plain index-based virtualized list: a group header and a data row are both
/// just rows at some index.
sealed class GridRow<T> {
  const GridRow({required this.index, required this.depth});

  /// Position of this row in the flattened, currently visible list.
  final int index;

  /// Indentation level: 0 when ungrouped.
  final int depth;
}

/// A row backed by one item of the data source.
/// A row's place in a tree.
///
/// One object rather than three fields on [DataGridRow], and null for the
/// flat and grouped cases. A grouped 50k-row grid allocates a [DataGridRow]
/// per visible row every time anything changes, and an ungrouped one builds
/// them on every read, so what those objects cost to construct is a
/// measurable part of a group toggle. A tree pays one small allocation per
/// row it actually nests; everything else pays one null field.
class TreeRowInfo {
  const TreeRowInfo({
    required this.path,
    required this.hasChildren,
    required this.expanded,
  });

  /// Identity of this row within the tree, built from its ancestors' keys.
  ///
  /// Used to remember which branches are open, exactly as a group's path is.
  final String path;

  /// Whether this row has rows of its own beneath it.
  final bool hasChildren;

  /// Whether this row's children are shown.
  final bool expanded;

  @override
  String toString() => 'TreeRowInfo($path)';
}

class DataGridRow<T> extends GridRow<T> {
  const DataGridRow({
    required super.index,
    required this.data,
    required this.sourceIndex,
    super.depth = 0,
    this.tree,
  });

  final T data;

  /// Index of [data] in the unsorted, unfiltered source list, or -1 when the
  /// source cannot provide one (remote paging).
  final int sourceIndex;

  /// This row's place in the hierarchy, or null in a flat or grouped grid.
  final TreeRowInfo? tree;

  /// Identity of this row within a tree, empty in a flat or grouped grid.
  String get treePath => tree?.path ?? '';

  /// Whether this row is a parent, i.e. it has rows of its own beneath it.
  ///
  /// Always false in a flat or grouped grid, so an adapter can ask any row
  /// without first asking what kind of grid it is in.
  bool get hasChildren => tree?.hasChildren ?? false;

  /// Whether this row's children are shown. Meaningless unless
  /// [hasChildren].
  bool get expanded => tree?.expanded ?? true;

  @override
  String toString() => 'DataGridRow($index <- $sourceIndex)';
}

/// A collapsible group header row.
class GroupGridRow<T> extends GridRow<T> {
  const GroupGridRow({
    required super.index,
    required super.depth,
    required this.node,
    required this.expanded,
    this.loading = false,
  });

  final GroupNode<T> node;
  final bool expanded;

  /// Whether the grid is waiting for this group's contents.
  ///
  /// Only ever true for a lazily grouped source: the header is on screen, the
  /// rows are in flight, and the adapter should say so rather than leave an
  /// open group looking empty.
  final bool loading;

  /// Whether this group's contents are in hand. False for a header whose rows
  /// a lazy source has not been asked for yet.
  bool get isLoaded => node.loaded;

  String get field => node.field;
  Object? get key => node.key;
  String get label => node.label;
  String get path => node.path;
  int get rowCount => node.rowCount;
  AggregateResult get aggregates => node.aggregates;

  @override
  String toString() => 'GroupGridRow($path, $rowCount rows)';
}

/// Tracks which group paths are open.
///
/// Expansion is keyed by [GroupNode.path] rather than by object identity, so
/// it survives re-sorting, re-filtering and data reloads.
class GroupExpansionState {
  GroupExpansionState({Set<String>? expanded, this.expandedByDefault = true})
      : _overrides = expanded?.toSet() ?? <String>{};

  /// Whether a group not yet touched by the user counts as open.
  final bool expandedByDefault;

  /// Paths whose state differs from [expandedByDefault].
  final Set<String> _overrides;

  /// The paths the user has changed from the default, for a saved view.
  ///
  /// Saving the overrides rather than the open paths is what lets a restored
  /// view stay correct when the data has grown: a group the user never
  /// touched takes the grid's default, whenever it first appeared.
  Set<String> get overrides => Set.unmodifiable(_overrides);

  /// Replaces the override set, as restoring a saved view does.
  void setOverrides(Iterable<String> paths) {
    _overrides
      ..clear()
      ..addAll(paths);
  }

  bool isExpanded(String path) =>
      _overrides.contains(path) ? !expandedByDefault : expandedByDefault;

  void toggle(String path) {
    if (!_overrides.remove(path)) _overrides.add(path);
  }

  void setExpanded(String path, bool expanded) {
    if (expanded == expandedByDefault) {
      _overrides.remove(path);
    } else {
      _overrides.add(path);
    }
  }

  /// Opens every group.
  void expandAll() => _overrides.clear();

  /// Closes every group, including ones not yet seen.
  void collapseAll(Iterable<String> knownPaths) {
    _overrides.clear();
    if (expandedByDefault) _overrides.addAll(knownPaths);
  }

  GroupExpansionState copy() => GroupExpansionState(
        expanded: _overrides,
        expandedByDefault: expandedByDefault,
      );
}

/// Flattens [nodes] into visible rows, skipping the contents of collapsed
/// groups.
List<GridRow<T>> flattenGroups<T>(
  List<GroupNode<T>> nodes,
  GroupExpansionState expansion, {
  Set<String> loadingPaths = const {},
}) {
  final out = <GridRow<T>>[];
  void walk(List<GroupNode<T>> level) {
    for (final node in level) {
      final expanded = expansion.isExpanded(node.path);
      out.add(GroupGridRow<T>(
        index: out.length,
        depth: node.depth,
        node: node,
        expanded: expanded,
        loading: loadingPaths.contains(node.path),
      ));
      if (!expanded) continue;
      // An open group whose rows have not arrived yet shows its header and
      // nothing under it, rather than claiming to be empty.
      if (!node.loaded) continue;
      if (node.isLeafGroup) {
        for (final row in node.rows) {
          out.add(DataGridRow<T>(
            index: out.length,
            data: row,
            sourceIndex: -1,
            depth: node.depth + 1,
          ));
        }
      } else {
        walk(node.children);
      }
    }
  }

  walk(nodes);
  return out;
}

/// A read-only row list that materialises each [DataGridRow] on demand.
///
/// An ungrouped grid of 50k rows would otherwise allocate 50k wrapper objects
/// every time anything changed, which cost more than the sort that preceded
/// it. Adapters only ever touch the rows in the viewport, so the wrappers are
/// built as they are read.
///
/// Because a wrapper is created per read, two reads of the same index are
/// equal in content but not identical. Compare [DataGridRow.data] or
/// [GridRow.index] rather than identity.
class LazyDataRowList<T> extends ListBase<GridRow<T>> {
  LazyDataRowList(this._rows, {this.offset = 0, T Function(T row)? substitute})
      : _substitute = substitute;

  final List<T> _rows;

  /// Index of the first row in the unfiltered source, for remote paging.
  final int offset;

  /// Replaces a row as it is read, or null to read it through unchanged.
  ///
  /// This is how an edit that has been committed but not yet confirmed by a
  /// remote source stays on screen: the substitution happens per read, so a
  /// grid with no pending write pays nothing for it.
  final T Function(T row)? _substitute;

  @override
  int get length => _rows.length;

  @override
  set length(int value) =>
      throw UnsupportedError('The grid row list is read-only.');

  @override
  GridRow<T> operator [](int index) {
    final row = _rows[index];
    final substitute = _substitute;
    return DataGridRow<T>(
      index: index,
      data: substitute == null ? row : substitute(row),
      sourceIndex: offset + index,
    );
  }

  @override
  void operator []=(int index, GridRow<T> value) =>
      throw UnsupportedError('The grid row list is read-only.');
}

/// Every group path in a tree, used by [GroupExpansionState.collapseAll].
List<String> collectGroupPaths<T>(List<GroupNode<T>> nodes) {
  final out = <String>[];
  void walk(List<GroupNode<T>> level) {
    for (final node in level) {
      out.add(node.path);
      walk(node.children);
    }
  }

  walk(nodes);
  return out;
}
