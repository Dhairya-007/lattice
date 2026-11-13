# Changelog

## 0.1.0

First release of the engine.

- `GridColumn`: typed accessors, formatters, comparators, width bounds,
  pinning, visibility and edit hooks.
- `GridController`: owns query state, selection, group expansion and the edit
  session, and exposes the flat row list an adapter renders.
- Sorting: multi-column, stable, custom comparators, explicit null placement.
- Filtering: serialisable condition/group tree with 16 operators, plus
  free-text search across visible columns.
- Grouping: nested levels, derived group keys, path-keyed expansion state that
  survives re-sorting and reloads.
- Aggregation: sum, average, min, max, count, distinct count and custom
  reducers, per group and grid-wide.
- Virtualization: uniform and variable row heights, scroll-to-reveal, and
  column windowing for wide grids.
- Layout: leading / scrolling / trailing panes for frozen columns, with
  stretch and last-column fit.
- Selection: single and multi row, single cell and rectangular ranges, with
  ctrl / shift semantics owned by the engine.
- Editing: validated sessions with commit and rollback.
- Export: RFC 4180 CSV, grouped CSV and tab-separated clipboard text.
- Data sources: `InMemoryDataSource` for local data, `AsyncDataSource` for
  remote, with token-guarded fetches so a stale response cannot overwrite a
  newer one.
