# Changelog

## 0.4.1

Package metadata only; no code change.

0.4.0's pubspec description and screenshot description were both over the
lengths pub.dev scores them against - 180 characters for the description,
160 for a screenshot's - which cost the package 20 of its points. Neither
limit is checked by `dart pub publish --dry-run`, and the upload itself
enforces a *different* screenshot limit (200), so the only way to find out
was to publish. Both are inside both limits now, and the pubspec says so
beside each one.

## 0.4.0

A customer read all ~7,000 lines of the engine, wrote a probe per suspected
defect, and sent back 79 confirmed bugs with the test that reproduces each
one. This release fixes 77 of them; the two it does not are named at the end,
with what to do instead. The suite is 699 tests, up from 590.

Six were data-integrity bugs - wrong values written, or user work lost - and
none of them were things a user could have diagnosed. Editing one of two
equal rows wrote to the other. "Case-insensitive" filters were
case-sensitive. A refused write stayed on screen. Undo silently skipped rows
it could not see, and then consumed the step anyway. Read the first section
even if you skip the rest.

### Breaking

Behavioural changes first, because they are the ones no compiler will point
at.

- **A case-insensitive filter is now actually case-insensitive.**
  `caseSensitive` defaults to false, and `equals`, `notEquals`, `isIn`, `>=`,
  `<=` and `between` all compared with the tiebreaking comparison a *sort*
  needs, so `equals: 'apple'` did not match `'Apple'`. A grid relying on the
  old behaviour was relying on the bug; pass `caseSensitive: true` to keep it.
- **Text columns sort case- and accent-insensitively by default.**
  `[banana, Cherry, apple]` sorted to `[Cherry, apple, banana]`, and `école`
  sorted after `zebra`. Pass a `comparator` to a column to get the code-unit
  order back. The folded key is computed once per row, so the new default is
  no slower.
- **`compareValues` ranks by type class before comparing.** Mixed-type
  columns used to compare across types by their string forms, which made the
  relation intransitive - `9 < 10`, `10 < '5'`, `'5' < 9` - so `List.sort`
  could order them differently between runs. `BigInt` compares as a number
  rather than as text.
- **Group and tree paths have a new format.** A path segment now names its
  field and tags its key's type, because `null` and `"null"`, and `1` and
  `"1"`, produced the same path - and two groups with one path share one
  expansion state and one lazy-load cache entry. A tree branch is keyed by
  its own row key rather than by the chain of its ancestors. Collapsed-group
  paths saved by 0.3.x no longer match, so a restored view opens with its
  groups expanded; nothing else in a saved view is affected. Build paths with
  `groupPathSegment`, or `GridController.treePathFor`, rather than by hand.
- **`GroupExpansionState.collapseAll()` takes no arguments.** It flipped
  through the paths it knew about, which could only close the groups already
  on screen; a group that arrived later opened itself again. It flips the
  default instead. `GridViewState` carries `groupsExpandedByDefault` so the
  mode survives a round trip.
- **`distinctValuesFor` returns `DistinctValues`, not `List<Object?>`.** The
  list is `values`, and `truncated` says whether the column holds more than
  the limit - which a bare list could not. It is also computed over the rows
  matching every filter *except* the column's own, so picking "Input" no
  longer leaves "Input" as the only value on offer, and a truncated list
  holds the smallest values rather than the first ones seen.
- **A data source that pages must honour `GridQuery.offset`.** Infinite
  scroll asks for one slice from where the last one ended; it used to ask
  from the top for everything loaded so far, so ten slices of 100 transferred
  5,500 rows to show 1,000. A source that ignores `offset` will now return
  the same rows repeatedly.
- **`exportCsv` honours collapsed groups.** The expansion state was accepted
  and never read, while the method documented itself as matching the screen.
  Pass `ExportOptions(respectCollapsed: false)` for the old behaviour.
- **Negative numbers export as numbers.** The formula sanitiser treated a
  leading `-` as the start of a formula, so every negative value in a numeric
  column exported as text and broke the sums the export existed to compute.
  A value that parses as a plain number is not sanitised, and a
  `ColumnType.number` column is not sanitised at all.
- **Clipboard text is quoted.** A cell containing a tab, a newline or a quote
  round-trips instead of pasting as two rows, and `parseClipboardText` reads
  the quoted fields Excel, Sheets and LibreOffice produce.
- **`coerceValue` accepts finite decimals only.** `num.tryParse` read `0x10`
  as 16 and `NaN` as a double, so pasting either stored a value nobody typed
  - and `numberRange` called NaN valid, because NaN compares false against
  every bound. Use `parseDecimal` for the same rule elsewhere.
- **`pageCount` is 1 while grouped.** Grouping needs every matching row, so
  paging has nothing to turn; the grid used to advertise pages `nextPage`
  could not reach.
- **Two columns sharing a field throw.** `columnsByField` kept one of them, so
  the other lost its filters, its sort and its editing with no error
  anywhere.
- **`moveColumn` counts display positions.** With a hidden column present,
  `moveColumn('a', 2)` landed at display position 1.
- **Malformed JSON throws `FormatException`, not `TypeError`.** One corrupt
  entry in a saved view is skipped with a warning rather than taking the
  whole view with it; pass `warnings:` to `GridViewState.fromJson` to collect
  what was dropped. A document from a future schema version is still refused.
- **`DataGridRow.sourceIndex` is the row's position in the source**, for
  grouped and tree rows as well. It used to report the position in the
  *sorted result*, which is a different number as soon as anything is sorted,
  and -1 for every grouped row.
- **`countDistinct` no longer counts null**, and `sum`/`average` ignore text
  reading `NaN` or `Infinity`, which used to make every total over the column
  NaN. `ColumnStats.mean` divides by the numbers it added up rather than by
  every non-null value, so `[10, 'n/a']` averages 10 and not 5.
- **`GridColumn.copyWith` has a `clear` flag per nullable field.** There was
  no way to *remove* a callback, so a column with a `setValue` could never be
  made read-only. Changing `field` also regenerates the default `Map`
  accessor instead of quietly reading the old field.
- **A listener that throws no longer stops the listeners after it**, in both
  `GridChangeNotifier` and `FetchSignal`. Every listener runs and the first
  error is rethrown afterwards.
- **`setDataSource` resets what belonged to the old source**: its lazily
  loaded groups and tree children, its errors, writes in flight, which detail
  panels were open, and the undo history.
- Smaller: `moveToNextEditableCell` returns null on a source that cannot save
  (as `beginEdit` already did); an out-of-range read on `DetailRowList`
  throws a `RangeError` instead of returning a phantom row; `restoreState`
  emits `GridChange.layout`; `GridQuery.needle` folds accents; a humanised
  title keeps an acronym whole (`HTTPStatus` → `HTTP Status`).

### Fixed

Data integrity:

- Editing one of two equal rows wrote to the other: `InMemoryDataSource`
  located the row with `indexOf`, which uses `==`, so records and
  freezed/equatable models were indistinguishable. Rows are located by
  identity, and a batch write builds one identity index instead of scanning
  per row.
- A write finishing wiped a newer write to the same row, so the cell went
  back to the older value while the newer one was still in flight. Pending
  writes are stamped with the write that owns them.
- A refused write was never rolled back on a model whose setter mutates in
  place: dropping the optimistic overlay put the overlay back, not the row.
  The previous values are captured before the setters run and replayed on
  failure.
- Undo resolved rows by scanning what was on screen, so a row on another
  page, inside a closed group or filtered out of view was skipped - and the
  step had already moved to the redo stack, which made that edit permanently
  unrepeatable. Rows resolve through the source, the history only moves when
  something was written, and `lastReplay` reports what was applied.
- Lazy group loads answered whichever query happened to be current when they
  landed, so a search typed while loads were in flight showed every
  pre-search row. Loads carry the fetch token and a source generation.
- Date filters could not be JSON-encoded at all (`jsonEncode` threw), and
  with a `toEncodable` they came back as strings and compared against
  instants by accident. Operands carry their type: `{"$date": "<iso>"}`.

Crashes, hangs and stuck state:

- A deep tree overflowed the stack at ~4,500 levels expanded, and at ~20,000
  collapsed. Flattening, root-marking and path collection use an explicit
  stack.
- `dispose()` left a debounced refresh pending for the life of the isolate,
  and a direct refresh did the same to a coalesced one it overtook.
- A source that maps an aborted request onto `FetchCancelled` left
  `isLoading` true for good.
- A grouped export with zero columns threw a `RangeError` from
  `List.filled(-1)`.
- A filter on a removed column hid every row, with no header left to clear it
  from. Filters, sorts and groupings whose field the grid no longer has are
  left out of the query and kept in state, so putting the column back brings
  the filter back; `inactiveFields` says which are parked.

Wrong state:

- `reload()` never refetched a lazy tree's children.
- An optimistic edit was invisible in tree and grouped views.
- After a failed fetch, the counts and aggregates described rows that were
  gone. `isStale` says when the rows on screen are left over.
- The page index was not clamped when the data shrank, so the grid showed
  nothing while rows sat on an earlier page.
- Group expansion leaked between grouping fields; group headers ignored the
  column's comparator (High/Medium/Low sorted alphabetically); the blank group
  jumped to the top when the headers were reversed (`GroupSpec.nulls`).
- A cell range outlived the rows it covered, and `CellRange.contains`
  disagreed with `coveredFields` once a field disappeared.
- A selected group header drifted onto another group when one above it
  collapsed.
- `ColumnFit.stretch` dumped the whole remainder on the last column;
  it fills like water now - `[110, 245, 245]`, not `[110, 200, 290]`.
- Copying a selection with a group header in it emitted a blank row; a paste
  across one dropped a row of the user's data instead of skipping to the next
  data row.
- A grouped CSV export indented every cell, so numbers became text.
- Committing a value the user had not changed still wrote to the server and
  refetched.
- A nested tree's children never saw the sort; `flattenNestedRows` converts a
  nested model into the flat rows and parent references the pipeline can
  filter, search and sort in full.
- `between` with its bounds typed backwards matched nothing; a filter operand
  is coerced to the column's type, so `'50'` in a number column compares as
  50; `isIn` conditions and `FilterGroup`s have value equality;
  `compareValuesNatural` orders digit runs longer than an `int64`;
  `compareValuesCaseInsensitive` folds the accents its doc always claimed to.

### Performance

Measured on one M4 laptop, median of 7 runs, against 0.3.0 on the same
machine. The benchmark gained a probe for each of these, with ceilings in
`benchmark/budgets.dart`, because the old gate missed every one of them.

| operation | 0.3.0 | 0.4.0 |
| --- | ---: | ---: |
| `isIn` over 1,000 values, 50k rows | 1,920 ms | 6.2 ms |
| natural sort, 50k rows | 2,405 ms | 46 ms |
| edit one cell with a search and a sort, 50k | 88 ms | 0.7 ms |
| the same at 200k | 371 ms | 3.5 ms |
| group toggle, 200k rows | 45 ms | 0.07 ms |
| conditional formatting, 40 x 200 cells | 13.5 ms | 1.2 ms |
| flatten a 4,000-deep tree | 110 ms | 2.4 ms |
| select-all, 1M rows | 109 ms | O(1) |
| read the scrollable band, 50k rows | 4.5 ms | 0.04 ms |

How: filters compile once per query rather than per row (pre-folded needles,
a `HashSet` for `isIn`, operands coerced); an expensive ordering computes one
key per row (`GridColumn.sortKey`, `naturalSortKey`); an edited row is
patched into each memoised stage instead of invalidating all of them, which a
randomised differential test holds to the same answer as a full recompute;
a grouped result is a `GroupedRowList` over an index of the groups, so a
toggle costs the groups and not the rows; select-all is a flag with a set of
exceptions; the frozen bands are views (`RowSlice`) rather than copies;
`sourceIndex` resolves on demand; and the column map is cached.

The README's claim of "~100k rows inside a frame budget" was never measured at
100k and was not true. It now says what the benchmark says: everything fits
in a frame to about 20k, sorting and a whole-table search cross it between
there and 100k, and past 100k the work belongs in a database.

### Added

- `foldText`, `compareValuesFolded`, `valuesEqualFolded`, `naturalSortKey`,
  `defaultCompareFor`, `sortOrder`.
- `GridColumn.sortKey` and `sortValue`: the value a column *orders* by,
  computed once per row per sort.
- `Filter.compile` and `CompiledFilter`, with `compileCondition`,
  `coerceFilterOperand`, `encodeFilterOperand`/`decodeFilterOperand` and
  `pruneFilter`. `FilterCondition.dateOnly` makes `equals` on a date column
  mean the day rather than the instant.
- `DistinctValues`; `LatticeDataSource.localRows` and `columnTypes`.
- `GroupedRowList`, `RowSlice`, `GroupNode.mapRows`, `groupPathSegment`,
  `pathKeySegment`, `GroupSpec.nulls`.
- `flattenNestedRows` and `NestedRows`; `flattenTree` takes a
  `childComparator`, a `substitute` and a `sourceIndexOf`.
- `GridController.treePathFor`, `inactiveFields`, `isStale`, `lastReplay`,
  `loadedRowCount`.
- `EditHistory.peekUndo`/`peekRedo`/`commitUndo`/`commitRedo` and
  `ReplayOutcome`, so an action is applied before the history moves.
- `SelectionState.isEverythingSelected` and `followedRows`;
  `CellRange.clampedTo`.
- `ExportOptions.respectCollapsed`; `parseDecimal`;
  `GridViewState.groupsExpandedByDefault`; `ColumnStats.numberCount`;
  `GridResult.sourceIndexOf`.

### Not fixed

- Search and filtering still only see the rows a data source holds, so a
  nested (`childrenOf`) tree matches on its roots. `flattenNestedRows` is the
  supported route, and keeping the ancestors of a match is still to come.
- `GroupSpec` and `Aggregation` compare their closures by identity, which is
  all Dart offers for a function. A spec built inline on every rebuild misses
  the pipeline cache every time; hoist the closure to a static or top-level
  function. The doc comment claiming otherwise has been corrected.


## 0.3.0

The release that makes the engine's own structure sound: identity instead of
position, stated capability instead of inferred type, and a notification that
says what changed. Five confirmed bugs are fixed with their causes, not their
symptoms, and the API is trimmed before 1.0 makes it a promise.

### Breaking

Each of these is a compile error or a one-line change, not a redesign.

- **`beginEdit` returns null when the data source cannot save.** A column with
  a setter is no longer editable on a source with nowhere to put the write;
  pass `onCommit:` to `AsyncDataSource`, or implement `canCommit` and `commit`.
  Refusing at the door is deliberate: the alternative is the user finding out
  after typing.
- **`visibleColumns`, `visibleFields` and `exportCsv` report screen order**,
  which differs from declaration order once a column is pinned. `ColumnFit.
  lastColumn` grows the last column on screen for the same reason. A grid with
  no pinned columns sees no change.
- **`GroupSpec` equality includes `keyOf`, `labelOf` and `blankLabel`.** Two
  specs that bucket rows differently used to compare equal, which is the bug
  that made regrouping serve stale buckets; code relying on that was relying
  on the bug.
- **`GridRow` has a new variant, `DetailGridRow`.** An exhaustive `switch` over
  rows needs a case for it. The compiler names every site.
- **The pipeline helpers moved to `package:lattice_core/advanced.dart`:**
  `sortRows`, `buildComparator`, `buildGroups`, `flattenGroups`,
  `collectGroupPaths`, `flattenTree`, `rootsOf`, `collectTreePaths`,
  `computeAggregates`, `computeColumnStats`, `describeHeaderProblems`, and the
  implementation types `LazyDataRowList`, `DetailRowList`, `FloatList` and
  `Float64ListLike`. Change the import; nothing was renamed. `RowMetrics`,
  `layoutHeaderRow`, `computeLayout` and `orderColumnsForDisplay` stay in the
  everyday library, because an adapter cannot draw without them.
- **`GridQuery.toJson` and `GridViewState.toJson` carry `"v": 1`.** Readers
  accept a document without it as version 1, so views saved by 0.2.x still
  restore; a document from a future version is refused with a
  `FormatException` rather than misread.

### Foundations

- **Rows can be identified rather than located.** `GridController.rowKey` makes
  the selection, the active cell and an open edit session follow their rows
  through a sort, a filter or a background refresh.
- **One display order.** `orderColumnsForDisplay` resolves the panes, and
  `computeLayout` uses it, so the layout, keyboard navigation, range selection
  and the export cannot disagree about which column is next to which.
- **Cache keys come from each spec.** `SortSpec.fingerprint`,
  `Aggregation.fingerprint`, `GroupSpec.fingerprint` and one
  `GridQuery` fingerprint per pipeline stage replace keys assembled by their
  callers out of the fields they remembered.
- **Sources declare what they can do.** `isSynchronous`/`fetchSync`,
  `canCommit`, `providesStats`, `providesDistinctValues`, `hasMore`,
  `supportsLazyGroups` and `supportsCancellation`, gathered into
  `SourceCapabilities`. The engine no longer asks
  `source is InMemoryDataSource`: any synchronous source gets the in-frame
  path, and an adapter can stop offering what a source cannot honour.
- **Notifications say what changed.** `GridChange` and `addChangeListener` let
  an adapter repaint only what a change touched - clicking a cell no longer
  looks like a new set of rows - and a batch notifies once for the union of
  what it did. `addListener` still works and can read `lastChanges`.
- **Invariants are tested against random arrangements.** 120 generated
  combinations of sorting, filtering, searching, grouping, paging, pinning and
  hiding, checked against the rules that have to hold for all of them. Three of
  them fail if the display-order bug is put back.
- **The benchmark runs in CI**, publishes its table to the job summary, and
  fails the build on a breach of the ceilings in `benchmark/budgets.dart`.

### Fixed

- **Column order followed the column list, not the screen.** Pinning moves a
  column on screen without moving it in the list, so arrow keys skipped
  columns, a range selection covered cells that were not next to each other,
  and a CSV export's header did not match the header the user was looking at.
  `orderColumnsForDisplay` resolves the panes, and `visibleColumns`,
  `visibleFields` and `exportCsv` read it.
- **A selection followed the screen position, not the row.** Indices are what
  an adapter renders, so selecting a row and then sorting left the selection
  on whatever row had moved into that slot - and a background refresh of an
  async source could move it silently. `GridController.rowKey` makes rows
  recognisable; the selection, the active cell and an open edit session are
  rewritten to wherever their rows went.
- **The group cache ignored `keyOf` and `labelOf`.** The memo key was
  `field:direction`, so regrouping the same field with a different bucketing
  function served the previous buckets. `GroupSpec.fingerprint` carries both,
  and `GroupSpec` equality no longer claims two differently bucketed specs are
  the same.
- **Edits to anything but an in-memory source were lost.** `commitEdit`
  invalidated the source and let the grid re-fetch, which threw the new value
  away: the commit reported success and the cell went back to the old text.
  See the write path below.

### Added

- **A write path on `LatticeDataSource`.** `canCommit`, `commit(original,
  updated)` and `commitAll` for a batch. The controller applies a write
  optimistically, keeps it across the re-fetch that follows, and rolls it back
  with `writeError` set if the source throws. `beginEdit` refuses a source
  that cannot save, so the user learns before typing rather than after.
- **Cancellation and debounce.** `GridQuery.signal` is a `FetchSignal` the
  grid cancels when a newer query supersedes the fetch, so a source can abort
  the request instead of running it to completion for an answer nobody will
  read. `fetchDebounce` folds the interactions a user drives a character at a
  time - the search box, the filter row - into one request, for non-local
  sources only.
- **Server-side and lazy grouping.** `GridQuery.lazyGroups` asks a source
  that can for group headers and counts alone, and
  `fetchGroupChildren` resolves a group when the user opens it. Grouping no
  longer means downloading every matching row.
- **Saved views.** `GridViewState` carries the ordering, the filters, the
  search, the grouping, which groups are closed, the page, and the column
  widths, order, pinning and visibility, as plain JSON.
  `saveState`/`restoreState` apply it in one query, and `GridQuery.fromJson`
  and `GroupSpec.fromJson` complete the round trip.
- **Paste into a cell range.** `pasteText` is the inverse of
  `copySelectionAsText`: it parses the text, coerces each cell into its
  column's type, validates it, and writes the block as one change - all or
  nothing by default.
- **Undo and redo.** `undo()`, `redo()` and a bounded `EditHistory` over
  committed edits. History is per cell, so it works for an in-place row model
  as well as an immutable one, and per action, so a paste comes back in one
  step.
- **The filter metadata `ColumnType` already promised.**
  `operatorsFor(ColumnType)` ships the operator set, with `needsValue`,
  `needsSecondValue` and `defaultLabel` for the control beside it.
  `distinctValuesFor(field)` gives a checkbox filter its values, cached like
  `statsFor`. `GridResult.stats` lets a remote source supply the ranges
  conditional formatting needs - a data bar over a server-paged column drew
  nothing before.
- **Auto-sizing.** `autoSizeColumn(field, measure:)` and `autoSizeColumns`
  sample the rows and ask the caller to measure the text, which is the one
  thing the engine cannot do itself.
- **Tree data.** `TreeSpec`, with either `childrenOf` for a nested model or
  `parentOf` for a flat table with a parent reference, shows rows as a
  hierarchy - an org chart, a file browser, a bill of materials - as distinct
  from grouping, whose parents are invented from a shared value.
- `Aggregation.format`, so a count of prices can read as a number of rows and
  a sum as an amount of money.
- `movePages`, `moveToLineEdge`, `moveToGridEdge` and
  `moveToNextEditableCell`: PageUp/PageDown, Home/End and Tab-to-next-editable
  as engine behaviour rather than arithmetic in a widget.
- `keepRowsOnError`, off by default, keeps the last good rows on screen when a
  poll fails instead of blanking the grid.
- **Loading more instead of paging** (#25). `loadMoreSize` turns the grid into
  an accumulating list: the first fetch asks for one slice and each
  `loadMore()` appends another, with `canLoadMore` false while a request is
  out so a scroll that reaches the end twice asks once. Changing the ordering
  or the filter starts again from one slice. `reload()` is what pull to
  refresh means.
- **Detail panels** (#14). `DetailGridRow` is a row in the flat list, so
  virtualization and the frozen bands count it, and its height is stated
  rather than measured because a prefix-sum table cannot wait for a layout
  pass. `toggleDetail` is keyed by row identity, so a sort cannot move a panel
  onto another row, and an open panel does not cost a 50k-row
  materialisation.
- **Lazily loaded tree children** (#15). `TreeSpec.childrenLoader` fetches a
  branch when it is opened, `hasChildren` draws the control before the
  children exist, a loading branch says so rather than looking empty, and one
  that fails reports through `childrenError` without being retried every
  frame.
- **`GroupSpec.blankLabel`** (#28), so the one piece of user-visible text the
  engine owns can be given in any language. It is a field rather than a
  lookup because `lattice_core` must not grow a dependency on anyone's
  localisations; the validator messages have always taken theirs the same
  way.

## 0.2.0

New API, nothing removed or renamed.

### Stacked headers

Header rows that span several columns, for grids where columns belong
together — four quarters, a street/city/postcode address.

- `HeaderBand` names the **fields** it covers rather than a column range, so
  it follows a reorder, narrows when a column is hidden, and splits correctly
  across a frozen pane.
- `layoutHeaderRow` resolves a row against one pane's columns, handling bands
  split across panes, bands interrupted by a moved column, and columns no
  band covers.
- `describeHeaderProblems` reports unknown fields, doubly-covered columns and
  empty bands; `GridController.stackedHeaders` runs it in an assertion, so a
  typo is loud in development and harmless in production.

### Frozen rows

`frozenRowCount` and `frozenRowCountBottom` pin rows to the top and bottom.

Pinning is by **position, not identity**: sort the grid and the pinned rows
are whatever now sorts first, which is what "frozen" should mean. The two
bands together are capped at one row fewer than the grid holds, so freezing
can never leave nothing to scroll — `effectiveFrozenTop` and
`effectiveFrozenBottom` report what you actually got.

### Selection coverage

`SelectionCoverage` (none / some / all) behind a tri-state select-all,
`toggleSelectAll`, and `setRowSelected` for toggling one row without
replacing the selection the way a click does. Coverage counts only rows that
still exist, so indices stranded by a filter cannot make a partial selection
look complete.

### Also

- `homepage` in the pubspec, and a `dart doc` check in CI so a broken
  reference in a doc comment fails the build rather than quietly degrading
  the published API documentation.
- Corrects the 0.1.0 entry below, which filed the export hardening and the
  conditional formatting API under "Unreleased" when both in fact shipped in
  0.1.0. A published archive is immutable, so the correction appears here.

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
