# Changelog

## Unreleased

- Conditional formatting rendered from the engine's rules: data bars drawn
  behind the value so they cost it no room, tone-coloured text, and tinted
  backgrounds whose strength follows the rule's intensity.
- `GridDensity.compact`, `.standard` and `.comfortable`, adjusting row,
  header and filter heights and cell padding together.
- Sticky group headers: the group you are scrolled inside stays named at the
  top of the viewport. Rebuilds against the scroll controller alone, so
  pinning costs one small widget per frame rather than a grid rebuild.
- `highlightChanges` flashes a cell when its value changes, for live data. It
  requires `rowId`: without a stable identity a row scrolling into a slot
  cannot be told from a value changing.
- Selection now happens on tap-down. A `GestureDetector` carrying both
  `onTap` and `onDoubleTap` cannot report the single tap until the
  double-tap window closes, which made every click feel late.
- Fixed: a page size not present in `pageSizes` replaced the footer with an
  error widget.

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
