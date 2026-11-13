/// The flat list of visual rows a UI adapter renders.
library;

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
class DataGridRow<T> extends GridRow<T> {
  const DataGridRow({
    required super.index,
    required this.data,
    required this.sourceIndex,
    super.depth = 0,
  });

  final T data;

  /// Index of [data] in the unsorted, unfiltered source list, or -1 when the
  /// source cannot provide one (remote paging).
  final int sourceIndex;

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
  });

  final GroupNode<T> node;
  final bool expanded;

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
  GroupExpansionState expansion,
) {
  final out = <GridRow<T>>[];
  void walk(List<GroupNode<T>> level) {
    for (final node in level) {
      final expanded = expansion.isExpanded(node.path);
      out.add(GroupGridRow<T>(
        index: out.length,
        depth: node.depth,
        node: node,
        expanded: expanded,
      ));
      if (!expanded) continue;
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
