# Changelog

## Unreleased

- **Security:** CSV and clipboard exports now neutralise values a spreadsheet
  would execute as a formula (`=`, `+`, `-`, `@`, tab, carriage return),
  including ones hidden behind leading spaces or a group indent. On by
  default; turn it off with `ExportOptions.sanitizeFormulas: false` for a
  machine-read export that must round-trip exactly.
- Conditional formatting: `DataBarRule`, `ColorScaleRule`, `ThresholdRule`,
  `ValueToneRule`, and `FirstMatchRule`/`MergedRule` to compose them, with
  per-column `ColumnStats` cached alongside the pipeline.
- Large datasets: the pipeline is memoised in three stages, quick search runs
  against a prebuilt index and narrows incrementally, sort keys are extracted
  once per row, and an ungrouped row list is materialised lazily. At 50k rows
  a page change went from 45 ms to 0.01 ms and a search keystroke from 60 ms
  to 6.5 ms.

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
