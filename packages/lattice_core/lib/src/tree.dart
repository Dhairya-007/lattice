/// Hierarchical rows: a row that is the parent of other rows.
library;

import 'group.dart';
import 'rows.dart';

/// How the rows form a hierarchy.
///
/// Grouping and a tree look alike on screen and are not the same thing.
/// Grouping invents a parent row out of a shared value - a header for
/// "Compute" that is not in the data. A tree's parents are rows: an employee
/// with reports, a folder with files, an assembly with parts. They can be
/// selected, edited and exported like any other row, and the demo's manager
/// column is one that could not be shown as what it is.
///
/// Give exactly one of [childrenOf] and [parentOf]: a nested model knows its
/// children, a flat one knows its parent.
class TreeSpec<T> {
  const TreeSpec({
    this.childrenOf,
    this.parentOf,
    this.childrenLoader,
    this.hasChildren,
  }) : assert(
          (childrenOf == null ? 0 : 1) +
                  (parentOf == null ? 0 : 1) +
                  (childrenLoader == null ? 0 : 1) ==
              1,
          'Give exactly one of childrenOf, parentOf and childrenLoader',
        );

  /// A row's children, for a model that nests them.
  ///
  /// Returning an empty list makes the row a leaf.
  final List<T> Function(T row)? childrenOf;

  /// The key of a row's parent, for a flat model with a parent reference -
  /// `managerId`, `parentId`, `folderId`.
  ///
  /// Null means the row is a root. A key that matches no row in the current
  /// result also makes the row a root, so filtering out a manager leaves
  /// their reports visible instead of dropping them off the grid.
  final Object? Function(T row)? parentOf;

  /// Fetches a row's children when its branch is first opened.
  ///
  /// For data that is a tree on a server: a file listing, an org chart one
  /// level at a time. The grid asks once per row, keeps what comes back, and
  /// marks the branch as loading in between so an open branch does not look
  /// like an empty one.
  final Future<List<T>> Function(T row)? childrenLoader;

  /// Whether a row has children, where that is known before they arrive.
  ///
  /// A lazily loaded tree has to draw a disclosure control before it knows
  /// what is underneath, and the answer usually travels with the row - a
  /// folder flag, a child count. Without it a row is drawn as a leaf until it
  /// is opened, which is the one thing a user cannot do to it.
  final bool Function(T row)? hasChildren;

  bool get isNested => childrenOf != null;

  /// Whether children arrive asynchronously.
  bool get isLazy => childrenLoader != null;
}

/// Flattens [rows] into the visible rows of a tree, skipping what is closed.
///
/// A row's path is its own key, type-tagged, and not the chain of its
/// ancestors: a row is rendered once whatever claims it, so its key already
/// identifies it, and repeating every ancestor made the paths grow
/// quadratically with depth - 36MB of path characters over a 4,000-deep
/// chain, which is 110ms of flattening spent building strings nobody reads.
///
/// A row that is reachable twice - a cycle in a parent reference, or a child
/// listed under two parents - is rendered once, under the first parent that
/// claims it. A grid that hangs is a worse answer to bad data than a grid
/// that is missing a branch.
///
/// [childComparator] orders the children of each row, which is how a sort on
/// a nested model reaches past its roots: the pipeline only ever sees the
/// rows the data source holds, so for a `childrenOf` model it sorts the roots
/// and nothing else. [substitute] replaces a row as it is read, so an
/// optimistic write shows up on a child too.
List<GridRow<T>> flattenTree<T>({
  required List<T> rows,
  required TreeSpec<T> spec,
  required Object Function(T row) keyOf,
  required GroupExpansionState expansion,
  Map<Object, List<T>> loadedChildren = const {},
  Set<Object> loadingKeys = const {},
  Comparator<T>? childComparator,
  T Function(T row)? substitute,
  int Function(T row)? sourceIndexOf,
}) {
  final out = <GridRow<T>>[];
  final seen = <Object>{};

  final childrenOf = spec.childrenOf;
  final parentOf = spec.parentOf;

  // The flat form: index the rows by their parent's key once, rather than
  // scanning every row per parent.
  final byParent = <Object, List<T>>{};
  final present = <Object>{};
  if (parentOf != null) {
    for (final row in rows) {
      present.add(keyOf(row));
    }
    for (final row in rows) {
      final parent = parentOf(row);
      if (parent == null || !present.contains(parent)) continue;
      byParent.putIfAbsent(parent, () => <T>[]).add(row);
    }
  }

  List<T> rawChildren(T row) {
    if (childrenOf != null) return childrenOf(row);
    if (spec.isLazy) return loadedChildren[keyOf(row)] ?? const [];
    return byParent[keyOf(row)] ?? const [];
  }

  List<T> children(T row) {
    final kids = rawChildren(row);
    if (childComparator == null || kids.length < 2) return kids;
    // A nested model's children never reach the pipeline, so the sort the
    // user asked for is applied to each level here.
    return List<T>.of(kids)..sort(childComparator);
  }

  /// Whether a disclosure control belongs on this row.
  ///
  /// A lazily loaded row may have children nobody has asked for yet, so the
  /// spec is asked first and the loaded children are only a fallback.
  bool mayHaveChildren(T row, List<T> loaded) {
    final declared = spec.hasChildren?.call(row);
    if (declared != null) return declared;
    return loaded.isNotEmpty;
  }

  // An explicit stack, not recursion: a folder tree or a bill of materials
  // from real data reaches thousands of levels, and the recursive version
  // overflowed the stack between 4,500 and 5,000 of them - a crash with no
  // bad input to point at.
  void walk(List<T> roots) {
    final stack = <_Pending<T>>[];
    for (var i = roots.length - 1; i >= 0; i--) {
      stack.add(_Pending<T>(roots[i], 0));
    }
    while (stack.isNotEmpty) {
      final pending = stack.removeLast();
      final row = pending.row;
      final key = keyOf(row);
      if (!seen.add(key)) continue;
      final kids = children(row);
      final expanded = expansion.isExpanded(pathKeySegment(key));
      out.add(DataGridRow<T>(
        index: out.length,
        data: substitute == null ? row : substitute(row),
        sourceIndexOf: sourceIndexOf,
        depth: pending.depth,
        tree: TreeRowInfo(
          path: pathKeySegment(key),
          hasChildren: mayHaveChildren(row, kids),
          expanded: expanded,
          loading: loadingKeys.contains(key),
        ),
      ));
      if (kids.isEmpty || !expanded) continue;
      for (var i = kids.length - 1; i >= 0; i--) {
        stack.add(_Pending<T>(kids[i], pending.depth + 1));
      }
    }
  }

  if (parentOf == null) {
    walk(rows);
    return out;
  }
  walk(rootsOf<T>(rows, parentOf, keyOf, present, children));
  return out;
}

/// One row waiting to be flattened, with the depth it will be drawn at.
class _Pending<T> {
  _Pending(this.row, this.depth);

  final T row;
  final int depth;
}

/// The rows to draw at depth zero of a flat, parent-referencing model.
///
/// A row is a root when it names no parent, or names one that is not in the
/// result - filtering out a manager leaves their reports visible rather than
/// dropping them. Rows that no root can reach are roots too: a cycle has no
/// root of its own, and its rows would otherwise vanish from the grid
/// altogether. A row drawn at the wrong depth is recoverable; a row that is
/// not drawn at all is not.
List<T> rootsOf<T>(
  List<T> rows,
  Object? Function(T row) parentOf,
  Object Function(T row) keyOf,
  Set<Object> present,
  List<T> Function(T row) childrenOf,
) {
  final roots = [
    for (final row in rows)
      if (parentOf(row) == null || !present.contains(parentOf(row))) row,
  ];

  // Reachability ignores expansion: a child hidden under a closed branch is
  // placed, it is just not on screen. Marked with an explicit stack, because
  // this walks the whole tree whether or not anything is open - a collapsed
  // 20,000-deep chain used to overflow here while the grid showed one row.
  final reachable = <Object>{};
  final stack = <T>[...roots];
  while (stack.isNotEmpty) {
    final row = stack.removeLast();
    if (!reachable.add(keyOf(row))) continue;
    stack.addAll(childrenOf(row));
  }
  if (reachable.length == rows.length) return roots;
  return [
    ...roots,
    for (final row in rows)
      if (!reachable.contains(keyOf(row))) row,
  ];
}

/// Every tree path in [rows], for collapsing a tree whose branches the user
/// has never opened.
List<String> collectTreePaths<T>({
  required List<T> rows,
  required TreeSpec<T> spec,
  required Object Function(T row) keyOf,
}) {
  final out = <String>[];
  final seen = <Object>{};
  final childrenOf = spec.childrenOf;
  final parentOf = spec.parentOf;

  final byParent = <Object, List<T>>{};
  final present = <Object>{};
  if (parentOf != null) {
    for (final row in rows) {
      present.add(keyOf(row));
    }
    for (final row in rows) {
      final parent = parentOf(row);
      if (parent == null || !present.contains(parent)) continue;
      byParent.putIfAbsent(parent, () => <T>[]).add(row);
    }
  }

  void walk(List<T> roots) {
    final stack = <T>[...roots.reversed];
    while (stack.isNotEmpty) {
      final row = stack.removeLast();
      final key = keyOf(row);
      if (!seen.add(key)) continue;
      out.add(pathKeySegment(key));
      final kids =
          childrenOf != null ? childrenOf(row) : (byParent[key] ?? const []);
      for (var i = kids.length - 1; i >= 0; i--) {
        stack.add(kids[i]);
      }
    }
  }

  if (parentOf == null) {
    walk(rows);
    return out;
  }
  walk(
    rootsOf<T>(
      rows,
      parentOf,
      keyOf,
      present,
      (row) => byParent[keyOf(row)] ?? const [],
    ),
  );
  return out;
}

/// Flattens a nested model into the rows and parent references a grid can
/// filter, search and sort.
///
/// A `childrenOf` model only ever hands the grid its roots, so the pipeline
/// has nothing else to work on: searching for a child's name matched nothing,
/// because no row the data source held carried that name. Put the result of
/// this in the data source and use `TreeSpec(parentOf: ...)` with the
/// returned lookup, and every stage sees every row.
///
/// ```dart
/// final flat = flattenNestedRows<Node>(
///   roots,
///   childrenOf: (n) => n.children,
///   keyOf: (n) => n.id,
/// );
/// final grid = GridController<Node>(
///   columns: columns,
///   dataSource: InMemoryDataSource<Node>(flat.rows),
///   rowKey: (n) => n.id,
///   tree: TreeSpec<Node>(parentOf: flat.parentOf),
/// );
/// ```
NestedRows<T> flattenNestedRows<T>(
  List<T> roots, {
  required List<T> Function(T row) childrenOf,
  required Object Function(T row) keyOf,
}) {
  final rows = <T>[];
  final parents = <Object, Object>{};
  final seen = <Object>{};
  final stack = <T>[...roots.reversed];
  while (stack.isNotEmpty) {
    final row = stack.removeLast();
    final key = keyOf(row);
    if (!seen.add(key)) continue;
    rows.add(row);
    final kids = childrenOf(row);
    for (var i = kids.length - 1; i >= 0; i--) {
      parents[keyOf(kids[i])] = key;
      stack.add(kids[i]);
    }
  }
  return NestedRows<T>(rows, parents, keyOf);
}

/// The flat form of a nested model, from [flattenNestedRows].
class NestedRows<T> {
  const NestedRows(this.rows, this._parents, this._keyOf);

  /// Every row, parents before their children.
  final List<T> rows;

  final Map<Object, Object> _parents;
  final Object Function(T row) _keyOf;

  /// The parent reference to give [TreeSpec.parentOf].
  Object? parentOf(T row) => _parents[_keyOf(row)];
}
