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
    this.loading = false,
  });

  /// Identity of this row within the tree, built from its ancestors' keys.
  ///
  /// Used to remember which branches are open, exactly as a group's path is.
  final String path;

  /// Whether this row has rows of its own beneath it.
  final bool hasChildren;

  /// Whether this row's children are shown.
  final bool expanded;

  /// Whether the grid is waiting for this row's children.
  ///
  /// Only ever true for a lazily loaded tree: the row is on screen, its
  /// children are in flight, and an open branch should say so rather than
  /// look empty.
  final bool loading;

  @override
  String toString() => 'TreeRowInfo($path)';
}

class DataGridRow<T> extends GridRow<T> {
  const DataGridRow({
    required super.index,
    required this.data,
    int sourceIndex = -1,
    int Function(T row)? sourceIndexOf,
    super.depth = 0,
    this.tree,
  })  : _sourceIndex = sourceIndex,
        _sourceIndexOf = sourceIndexOf;

  final T data;

  final int _sourceIndex;
  final int Function(T row)? _sourceIndexOf;

  /// Index of [data] in the unordered, unfiltered source, or -1 when the
  /// source cannot say.
  ///
  /// A source that holds its rows locally answers this exactly, whatever the
  /// sort, the filter or the grouping - it used to report the row's position
  /// in the *sorted* result, which is a different number and was only ever
  /// right for an unsorted grid. A remote source that pages has no way to
  /// know, and reports -1.
  ///
  /// Resolved on demand. The answer is a lookup by row identity, and a
  /// grouped grid flattens every matching row on every toggle: paying for it
  /// per row whether or not anyone reads it put 8ms on a group toggle at 50k
  /// rows, for a number most grids never ask for.
  int get sourceIndex {
    if (_sourceIndex >= 0) return _sourceIndex;
    return _sourceIndexOf?.call(data) ?? _sourceIndex;
  }

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

  /// Whether the grid is waiting for this row's children to arrive.
  bool get isLoadingChildren => tree?.loading ?? false;

  @override
  String toString() => 'DataGridRow($index <- $sourceIndex)';
}

/// A panel opened under its row, for the fields a row has no room for.
///
/// A row of a grid holds a dozen fields and a record usually has more, so the
/// common answer is a panel underneath holding whatever the application wants
/// to draw. It is a row in the flat list rather than something the widget
/// layer bolts on, because everything that walks rows - virtualization,
/// scroll-to-reveal, keyboard navigation, the frozen bands - has to count it.
///
/// The engine decides that it is there and how tall it is; what goes in it is
/// the adapter's business.
class DetailGridRow<T> extends GridRow<T> {
  const DetailGridRow({
    required super.index,
    required this.data,
    required this.rowKey,
    required this.height,
    super.depth = 0,
  });

  /// The row this panel belongs to.
  final T data;

  /// Identity of that row, which is what the open state is keyed by.
  final Object rowKey;

  /// How tall the panel is, in logical pixels.
  ///
  /// Stated by the engine so that row offsets can be computed without
  /// measuring a widget: a prefix-sum table cannot wait for a layout pass.
  final double height;

  @override
  String toString() => 'DetailGridRow($rowKey)';
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
  GroupExpansionState({Set<String>? expanded, bool expandedByDefault = true})
      : _expandedByDefault = expandedByDefault,
        _overrides = expanded?.toSet() ?? <String>{};

  bool _expandedByDefault;

  /// Whether a group not yet touched by the user counts as open.
  ///
  /// Flipped by [collapseAll] and [expandAll], which is what lets them mean
  /// "every group" rather than "every group I have seen so far".
  bool get expandedByDefault => _expandedByDefault;

  /// Paths whose state differs from [expandedByDefault].
  final Set<String> _overrides;

  /// The paths the user has changed from the default, for a saved view.
  ///
  /// Saving the overrides rather than the open paths is what lets a restored
  /// view stay correct when the data has grown: a group the user never
  /// touched takes the grid's default, whenever it first appeared.
  Set<String> get overrides => Set.unmodifiable(_overrides);

  /// Replaces the override set, as restoring a saved view does.
  ///
  /// [expandedByDefault] restores the mode as well, because "collapse all"
  /// is recorded as the mode and not as a list of paths.
  void setOverrides(Iterable<String> paths, {bool? expandedByDefault}) {
    if (expandedByDefault != null) _expandedByDefault = expandedByDefault;
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

  /// Opens every group, including ones not yet seen.
  void expandAll() {
    _expandedByDefault = true;
    _overrides.clear();
  }

  /// Closes every group, including ones not yet seen.
  ///
  /// Enumerating the paths it knew about could only close the groups already
  /// on screen, so a group that arrived later - a new page, a changed filter,
  /// a lazily loaded level - opened itself again straight after a
  /// collapse-all. Flipping the default is the only version of this that
  /// means what it says.
  void collapseAll() {
    _expandedByDefault = false;
    _overrides.clear();
  }

  GroupExpansionState copy() => GroupExpansionState(
        expanded: _overrides,
        expandedByDefault: _expandedByDefault,
      );
}

/// Flattens [nodes] into visible rows, skipping the contents of collapsed
/// groups.
List<GridRow<T>> flattenGroups<T>(
  List<GroupNode<T>> nodes,
  GroupExpansionState expansion, {
  Set<String> loadingPaths = const {},
  int Function(T row)? sourceIndexOf,
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
            sourceIndexOf: sourceIndexOf,
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
  LazyDataRowList(
    this._rows, {
    this.offset = 0,
    T Function(T row)? substitute,
    int Function(T row)? sourceIndexOf,
  })  : _substitute = substitute,
        _sourceIndexOf = sourceIndexOf;

  final List<T> _rows;

  /// Index of the first row in the unfiltered source, for remote paging.
  final int offset;

  /// Replaces a row as it is read, or null to read it through unchanged.
  ///
  /// This is how an edit that has been committed but not yet confirmed by a
  /// remote source stays on screen: the substitution happens per read, so a
  /// grid with no pending write pays nothing for it.
  final T Function(T row)? _substitute;

  /// Where a row sits in the source, when the source can say.
  final int Function(T row)? _sourceIndexOf;

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
      sourceIndex: _sourceIndexOf == null ? offset + index : -1,
      sourceIndexOf: _sourceIndexOf,
    );
  }

  @override
  void operator []=(int index, GridRow<T> value) =>
      throw UnsupportedError('The grid row list is read-only.');
}

/// A read-only window onto part of a row list.
///
/// `sublist` copies, and copying a window onto a lazy row list materialises
/// every row in it: reading `scrollableRows` on an ungrouped 50k-row grid
/// built 50k wrapper objects, several times a frame, to show forty of them.
/// A slice reads through instead, so it costs nothing until it is indexed.
///
/// Row indices are not renumbered - they are positions in the full visible
/// list, which is what the selection, the frozen bands and scroll-to-reveal
/// all speak in.
class RowSlice<T> extends ListBase<GridRow<T>> {
  RowSlice(this._rows, this.start, this.end)
      : assert(start >= 0 && start <= end, 'an empty or forward range');

  final List<GridRow<T>> _rows;
  final int start;
  final int end;

  @override
  int get length {
    final count = end - start;
    return count < 0 ? 0 : count;
  }

  @override
  set length(int value) => throw UnsupportedError('A row slice is read-only.');

  @override
  GridRow<T> operator [](int index) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index', null, length);
    }
    return _rows[start + index];
  }

  @override
  void operator []=(int index, GridRow<T> value) =>
      throw UnsupportedError('A row slice is read-only.');
}

/// Inserts a [DetailGridRow] after every row whose panel is open, renumbering
/// the rows as it goes.
///
/// For a list that is already materialised - a grouped or tree flattening.
/// The flat case has [DetailRowList], which does the same thing without
/// building anything.
List<GridRow<T>> withDetailRows<T>(
  List<GridRow<T>> rows, {
  required Set<Object> open,
  required double height,
  required Object Function(T row) keyOf,
}) {
  if (open.isEmpty) return rows;
  final out = <GridRow<T>>[];
  for (final row in rows) {
    final renumbered = row is DataGridRow<T>
        ? DataGridRow<T>(
            index: out.length,
            data: row.data,
            sourceIndex: row.sourceIndex,
            depth: row.depth,
            tree: row.tree,
          )
        : row is GroupGridRow<T>
            ? GroupGridRow<T>(
                index: out.length,
                depth: row.depth,
                node: row.node,
                expanded: row.expanded,
                loading: row.loading,
              )
            : row;
    out.add(renumbered);
    if (row is! DataGridRow<T>) continue;
    final key = keyOf(row.data);
    if (!open.contains(key)) continue;
    out.add(DetailGridRow<T>(
      index: out.length,
      data: row.data,
      rowKey: key,
      height: height,
      depth: row.depth,
    ));
  }
  return out;
}

/// A row list that interleaves open detail panels without materialising
/// anything.
///
/// One open panel must not cost 50k wrapper objects, so the visual index is
/// resolved arithmetically: the panels are held as the sorted data indices
/// they belong to, and a read works out how many of them precede the index
/// being read.
class DetailRowList<T> extends ListBase<GridRow<T>> {
  DetailRowList(
    this._rows, {
    required List<int> openAt,
    required this.height,
    required this.keyOf,
    this.offset = 0,
    T Function(T row)? substitute,
    int Function(T row)? sourceIndexOf,
  })  : _openAt = openAt,
        _substitute = substitute,
        _sourceIndexOf = sourceIndexOf;

  final List<T> _rows;

  /// Data indices whose panel is open, ascending.
  final List<int> _openAt;

  final double height;
  final Object Function(T row) keyOf;
  final int offset;
  final T Function(T row)? _substitute;
  final int Function(T row)? _sourceIndexOf;

  @override
  int get length => _rows.length + _openAt.length;

  @override
  set length(int value) =>
      throw UnsupportedError('The grid row list is read-only.');

  /// How many open panels sit strictly before data index [row].
  int _openBefore(int row) {
    var low = 0;
    var high = _openAt.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_openAt[mid] < row) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Visual position of data index [row].
  int _positionOf(int row) => row + _openBefore(row);

  @override
  GridRow<T> operator [](int index) {
    // An out-of-range read is an error, not a row: returning the last row's
    // phantom panel for index 10 of a 3-row list hid the caller's bug and
    // put a row on screen that does not exist.
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index', null, length);
    }
    // The largest data index whose row starts at or before [index]. The
    // mapping is monotonic, so this is a binary search.
    var low = 0;
    var high = _rows.length - 1;
    var found = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_positionOf(mid) <= index) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    final substitute = _substitute;
    final raw = _rows[found];
    final data = substitute == null ? raw : substitute(raw);
    if (_positionOf(found) == index) {
      return DataGridRow<T>(
        index: index,
        data: data,
        sourceIndex: _sourceIndexOf == null ? offset + found : -1,
        sourceIndexOf: _sourceIndexOf,
      );
    }
    // The only other row at this position is the panel under that row.
    return DetailGridRow<T>(
      index: index,
      data: data,
      rowKey: keyOf(raw),
      height: height,
    );
  }

  @override
  void operator []=(int index, GridRow<T> value) =>
      throw UnsupportedError('The grid row list is read-only.');
}

/// Every group path in a tree.
///
/// [GroupExpansionState.collapseAll] no longer needs it - closing "every
/// group" cannot be a list of the groups currently on screen - but a caller
/// that wants to act on the paths it can see still can.
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

/// A grouped row list that resolves positions arithmetically instead of
/// materialising every row.
///
/// Flattening built a wrapper object per visible row, so opening or closing
/// one group rebuilt the whole list: 36 ms at 200k rows, three frames, for a
/// change that affects one subtree. This holds an index over the *groups* -
/// each one's first visual position and how many rows its subtree shows - and
/// resolves a read by walking down it. A toggle rebuilds the group index,
/// which is O(groups), and touches no row at all.
///
/// As with [LazyDataRowList], a wrapper is created per read: compare
/// [GridRow.index] or [DataGridRow.data] rather than identity.
class GroupedRowList<T> extends ListBase<GridRow<T>> {
  GroupedRowList(
    List<GroupNode<T>> nodes,
    this.expansion, {
    this.loadingPaths = const {},
    this.sourceIndexOf,
    T Function(T row)? substitute,
  })  : _substitute = substitute,
        _levels = _indexNodes<T>(nodes, expansion, 0);

  final GroupExpansionState expansion;
  final Set<String> loadingPaths;

  /// Where a row sits in the source, when the source can say.
  final int Function(T row)? sourceIndexOf;

  final T Function(T row)? _substitute;

  /// The top level of the group index, in display order.
  final List<_GroupSlot<T>> _levels;

  @override
  int get length =>
      _levels.isEmpty ? 0 : _levels.last.start + _levels.last.total;

  @override
  set length(int value) =>
      throw UnsupportedError('The grid row list is read-only.');

  @override
  GridRow<T> operator [](int index) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index', null, length);
    }
    var level = _levels;
    while (true) {
      final slot = _slotAt(level, index);
      final node = slot.node;
      if (index == slot.start) {
        return GroupGridRow<T>(
          index: index,
          depth: node.depth,
          node: node,
          expanded: expansion.isExpanded(node.path),
          loading: loadingPaths.contains(node.path),
        );
      }
      if (slot.children.isEmpty) {
        // A leaf group: the rows follow its header in order.
        final row = node.rows[index - slot.start - 1];
        return DataGridRow<T>(
          index: index,
          data: _substitute == null ? row : _substitute(row),
          sourceIndexOf: sourceIndexOf,
          depth: node.depth + 1,
        );
      }
      level = slot.children;
    }
  }

  @override
  void operator []=(int index, GridRow<T> value) =>
      throw UnsupportedError('The grid row list is read-only.');

  /// The slot in [level] whose span covers [index].
  ///
  /// The slots are contiguous and ascending, so this is a binary search: a
  /// grid grouped into thousands of groups must not walk them per read.
  static _GroupSlot<T> _slotAt<T>(List<_GroupSlot<T>> level, int index) {
    var low = 0;
    var high = level.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (level[mid].start <= index) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return level[low];
  }

  static List<_GroupSlot<T>> _indexNodes<T>(
    List<GroupNode<T>> nodes,
    GroupExpansionState expansion,
    int start,
  ) {
    final out = <_GroupSlot<T>>[];
    var cursor = start;
    for (final node in nodes) {
      final expanded = expansion.isExpanded(node.path);
      // A group whose contents have not arrived shows its header alone,
      // rather than claiming to be empty.
      final shows = expanded && node.loaded;
      final children = shows && !node.isLeafGroup
          ? _indexNodes<T>(node.children, expansion, cursor + 1)
          : <_GroupSlot<T>>[];
      final contents = !shows
          ? 0
          : (node.isLeafGroup
              ? node.rows.length
              : (children.isEmpty
                  ? 0
                  : children.last.start + children.last.total - cursor - 1));
      final total = 1 + contents;
      out.add(
          _GroupSlot<T>(node, cursor, total, children.cast<_GroupSlot<T>>()));
      cursor += total;
    }
    return out;
  }
}

/// One group's place in a [GroupedRowList]: where its header sits and how
/// many visual rows its subtree contributes.
class _GroupSlot<T> {
  _GroupSlot(this.node, this.start, this.total, this.children);

  final GroupNode<T> node;

  /// Visual index of this group's header.
  final int start;

  /// Rows this group's subtree shows, its header included.
  final int total;

  final List<_GroupSlot<T>> children;
}
