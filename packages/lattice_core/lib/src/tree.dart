/// Hierarchical rows: a row that is the parent of other rows.
library;

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
  const TreeSpec({this.childrenOf, this.parentOf})
      : assert(
          (childrenOf == null) != (parentOf == null),
          'Give exactly one of childrenOf and parentOf',
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

  bool get isNested => childrenOf != null;
}

/// Flattens [rows] into the visible rows of a tree, skipping what is closed.
///
/// Paths are built from [keyOf], the same identity the rest of the grid uses,
/// so expansion survives a re-sort or a reload - exactly as group expansion
/// does. The separator is a character a key is unlikely to contain; a key
/// that does contain it can only collide with another key that also does.
///
/// A row that is reachable twice - a cycle in a parent reference, or a child
/// listed under two parents - is rendered once, under the first parent that
/// claims it. A grid that hangs is a worse answer to bad data than a grid
/// that is missing a branch.
List<GridRow<T>> flattenTree<T>({
  required List<T> rows,
  required TreeSpec<T> spec,
  required Object Function(T row) keyOf,
  required GroupExpansionState expansion,
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

  List<T> children(T row) {
    if (childrenOf != null) return childrenOf(row);
    return byParent[keyOf(row)] ?? const [];
  }

  void walk(List<T> level, int depth, String parentPath) {
    for (final row in level) {
      final key = keyOf(row);
      if (!seen.add(key)) continue;
      final path = parentPath.isEmpty ? '$key' : '$parentPath\u001f$key';
      final kids = children(row);
      final expanded = expansion.isExpanded(path);
      out.add(DataGridRow<T>(
        index: out.length,
        data: row,
        sourceIndex: -1,
        depth: depth,
        treePath: path,
        hasChildren: kids.isNotEmpty,
        expanded: expanded,
      ));
      if (kids.isEmpty || !expanded) continue;
      walk(kids, depth + 1, path);
    }
  }

  if (parentOf == null) {
    walk(rows, 0, '');
    return out;
  }
  walk(rootsOf<T>(rows, parentOf, keyOf, present, children), 0, '');
  return out;
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
  // placed, it is just not on screen.
  final reachable = <Object>{};
  void mark(List<T> level) {
    for (final row in level) {
      if (!reachable.add(keyOf(row))) continue;
      mark(childrenOf(row));
    }
  }

  mark(roots);
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

  void walk(List<T> level, String parentPath) {
    for (final row in level) {
      final key = keyOf(row);
      if (!seen.add(key)) continue;
      final path = parentPath.isEmpty ? '$key' : '$parentPath\u001f$key';
      out.add(path);
      walk(
        childrenOf != null ? childrenOf(row) : (byParent[key] ?? const []),
        path,
      );
    }
  }

  if (parentOf == null) {
    walk(rows, '');
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
    '',
  );
  return out;
}
