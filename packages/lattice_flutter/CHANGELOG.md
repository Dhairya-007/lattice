# Changelog

## 0.1.0

First release of the Flutter adapter.

- `LatticeDataGrid`: virtualized rows, frozen leading and trailing columns,
  synchronised panes, and horizontal windowing for wide grids.
- Header: tap to sort, ctrl or cmd click for multi-column sort with level
  numbers, drag to resize, double tap a handle to reset the width.
- Optional filter row, with the operator chosen from the column type.
- Group rows: animated chevron, row counts and per-group aggregates shown
  under the column they belong to.
- Selection: row, cell and rectangular range, with keyboard navigation,
  ctrl or cmd + A to select all and ctrl or cmd + C to copy as TSV.
- Inline editing on double tap, Enter or F2, with validation errors shown in
  place and Escape to roll back.
- Footer: row and selection counts, grid-wide aggregates and pagination.
- `LatticeGridTheme`: derived from the ambient Material theme, fully
  overridable, light and dark.
