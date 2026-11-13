# Changelog

## 0.1.1

Documentation and metadata only — no change to the library.

- **Corrected the 0.1.0 entry.** It listed the export hardening and the
  conditional formatting API under "Unreleased", when both in fact shipped in
  0.1.0. Anyone reading the package page would have concluded the CSV
  formula-injection fix was still pending. The entry below now says what
  0.1.0 actually contains.
- Added `homepage` to the pubspec, and a `dart doc` check to CI so a broken
  reference in a doc comment fails the build rather than quietly degrading
  the published API documentation.

## 0.1.0

First release. The complete grid engine in pure Dart, with no dependency on
Flutter or any other UI toolkit.

### Core

- `GridColumn`: typed accessors, formatters, comparators, width bounds,
  pinning, visibility, edit hooks and conditional formatting rules.
- `GridController`: owns query state, selection, group expansion and the edit
  session, and exposes the flat row list an adapter renders.
- `GridQuery` and `GridResult`: one description of what the grid wants, which
  `InMemoryDataSource` executes locally and `AsyncDataSource` hands to a
  server. Fetches are token-guarded, so a slow response from an earlier query
  cannot overwrite a newer one.

### Data operations

- Sorting: multi-column, stable, custom comparators, explicit null placement
  that does not flip with the direction.
- Filtering: a serialisable condition/group tree with 16 operators, plus
  free-text search across visible columns. Half-filled conditions report
  `isEmpty` and are dropped rather than hiding every row.
- Grouping: nested levels, derived group keys, and expansion keyed by a key
  path so it survives re-sorting, re-filtering and reloads.
- Aggregation: sum, average, min, max, count, distinct count and custom
  reducers, per group and grid-wide. Numeric aggregates skip nulls like SQL,
  so an all-null group yields `null` rather than a misleading `0`.

### Presentation support

- Conditional formatting: `DataBarRule`, `ColorScaleRule`, `ThresholdRule`,
  `ValueToneRule`, and `FirstMatchRule`/`MergedRule` to compose them. Rules
  emit a semantic `CellTone` and an intensity rather than a colour, so one
  rule set reads correctly in light and dark.
- `ColumnStats`: per-column range, computed over the rows that currently
  match so data bars rescale with the filter.
- Virtualization: uniform and variable row heights, scroll-to-reveal, and
  column windowing for wide grids.
- Layout: leading / scrolling / trailing panes for frozen columns, with
  stretch and last-column fit.
- Selection: single and multi row, single cell and rectangular ranges, with
  ctrl / shift semantics owned by the engine, addressed by field so a
  selection survives columns being reordered or hidden.
- Editing: validated sessions with commit and rollback. A rejected commit
  keeps the session open with its error instead of discarding what was typed.

### Export

- RFC 4180 CSV, grouped CSV, and tab-separated clipboard text.
- **Formula injection is neutralised by default.** A value beginning `=`, `+`,
  `-`, `@`, tab or carriage return is executed when the file is opened in
  Excel, Sheets or LibreOffice, so such values are prefixed to be read as
  text. The prefix goes inside the RFC 4180 quotes, and detection looks past
  leading spaces, which spreadsheets trim on import and a grouped export
  adds as indentation. Turn it off with
  `ExportOptions.sanitizeFormulas: false` for a machine-read export that must
  round-trip exactly.

### Performance

Measured at 50k rows with `dart run benchmark/grid_benchmark.dart`:

- The pipeline is memoised in three stages — matched, ordered, grouped — each
  keyed by data revision and by the part of the query it depends on. A page
  change costs 0.01 ms instead of 45 ms; reversing a sort no longer
  re-filters.
- Quick search runs against a prebuilt per-row index and narrows within the
  previous match as you type: 6.5 ms per keystroke instead of 60 ms.
- Sort keys are extracted once per row rather than inside the comparator, and
  a single-column sort compares without type tests: 28 ms instead of 104 ms.
- An ungrouped row list is materialised lazily, so a 50k-row grid no longer
  allocates 50k wrapper objects whenever anything changes.

Grouping, filtering, paging, expansion and scroll lookups all sit inside a
16.7 ms frame at 50k rows. A large sort does not, and is documented as such:
beyond roughly 50k rows, sort through an `AsyncDataSource`.
