# lattice_core 0.3.0 — Top 50 bugs and top 50 additions

Tested 2026-11-16 against `lattice_core 0.3.0` from pub.dev (`hosted/pub.dev/lattice_core-0.3.0`), Dart 3.12.2, Windows x64, JIT.

## How this was tested

1. **Baseline.** The package's own suite passes (590/590), `dart analyze` is clean, and `benchmark/grid_benchmark.dart` runs. That benchmark already flags _sort by three columns_ as over the 16.7 ms frame at 50k rows (35 ms).
2. **Full read.** All ~7,000 lines of `lib/src` were read, and every suspected defect was written down as a candidate.
3. **Probes.** Each candidate became a test that asserts the _correct_ behaviour, so a failing probe is a confirmed bug. 83 correctness probes ran. 80 failed, which is 79 distinct issues once the P55/P55b duplicate is removed. 3 passed: P59 and P122 rule those candidates out (listed at the end), and P10 was superseded by the sharper P10b. Performance probes ran as a timed script (median of 7 runs, 3 for the slow ones).
4. **Nothing below is speculative.** Every item cites the probe that reproduces it. Where a sentence goes beyond what a probe tested, it says "by reading".

**Repro files:** `e:\flutter\lattice_demo\lattice_core_review_probes\`

- `zz_probe1_test.dart`, `zz_probe2_test.dart`, `zz_probe3_test.dart`: copy into `lattice_core/test/`. They import `fixtures.dart` from there. Run with `dart test test/zz_probe1_test.dart`.
- `zz_probe_perf.dart`: copy into `lattice_core/benchmark/` and run with `dart run benchmark/zz_probe_perf.dart`.

Each probe is named by ID (P01…P122, PF1…PF18). Once a bug is fixed, its probe should pass, so the files double as a regression suite.

Timings are from one Windows laptop on the JIT. Read them as ratios and growth rates rather than absolute figures. Your M-series numbers will be lower, but the 45× and the O(n²) curves will not change.

**Severity:** **Critical** = wrong data shown or written, or user work lost · **High** = crash, hang, or a performance cliff · **Medium** = wrong UI state or wrong output · **Low** = edge case or contract mismatch.

---

## Part 1 — Top 50 bugs

### Summary

| #   | Sev      | Area         | Bug                                                                             | Probe     |
| --- | -------- | ------------ | ------------------------------------------------------------------------------- | --------- |
| B01 | Critical | Editing      | Editing one of two equal rows writes to the other                               | P47       |
| B02 | Critical | Filter       | "Case-insensitive" equals / notEquals / isIn / range filters are case-sensitive | P05–P08   |
| B03 | Critical | Remote write | A finishing write wipes a newer pending write on the same row                   | P49       |
| B04 | Critical | Remote write | A refused write is never rolled back on mutable models                          | P50       |
| B05 | Critical | Undo         | Undo loses changes for rows not in view; a failed undo consumes history         | P45, P46  |
| B06 | Critical | Lazy groups  | Group loads from before a filter change are shown after it                      | P51       |
| B07 | High     | Rows         | `sourceIndex` is the sorted position, not the source index                      | P30       |
| B08 | High     | Data source  | `setDataSource` keeps lazy children (and other caches) from the old source      | P36       |
| B09 | High     | Lazy tree    | `reload()` never refetches lazy tree children                                   | P35       |
| B10 | High     | Remote write | Optimistic edits are invisible in tree and grouped views                        | P71       |
| B11 | High     | Saved views  | Date filters can't be JSON-encoded, and compare as strings after a round trip   | P09, P10b |
| B12 | High     | Filter       | A filter on a removed column keeps hiding every row                             | P44       |
| B13 | High     | Tree         | Deep trees overflow the stack (~5,000 levels expanded)                          | P61       |
| B14 | High     | Async        | `dispose()` leaves a debounced refresh future pending forever                   | P37       |
| B15 | High     | Async        | A direct refresh orphans an in-flight coalesced refresh                         | P121      |
| B16 | High     | Async        | A source that throws `FetchCancelled` leaves `isLoading` stuck at true          | P119      |
| B17 | High     | Saved views  | One malformed entry makes `GridViewState.fromJson` throw                        | P65, P113 |
| B18 | High     | Export       | Grouped export with zero columns throws `RangeError`                            | P53       |
| B19 | High     | Perf         | `isIn` is O(rows × values): 1.9 s for 1,000 values over 50k rows                | PF3       |
| B20 | High     | Perf         | `compareValuesNatural` is 45× slower than the default sort                      | PF2       |
| B21 | High     | Perf         | Conditional formatting eats 13.5 ms of the frame on a wide grid                 | PF13      |
| B22 | High     | Perf         | Tree paths grow quadratically with depth                                        | PF9       |
| B23 | High     | Perf         | Infinite scroll re-downloads everything on each `loadMore`                      | PF10      |
| B24 | Medium   | Perf         | README's "~100k rows inside a frame" claim is not met                           | PF1       |
| B25 | Medium   | Perf         | Editing one cell invalidates every pipeline cache (55 ms at 50k)                | PF5       |
| B26 | Medium   | Perf         | A group toggle rebuilds the whole flat list (36 ms at 200k)                     | PF16      |
| B27 | Medium   | Perf         | Select-all is O(n) everywhere                                                   | PF7, PF11 |
| B28 | Medium   | Perf         | `scrollableRows` / frozen bands materialise every lazy row                      | PF6       |
| B29 | Medium   | Selection    | A cell range outlives the rows it covered                                       | P32       |
| B30 | Medium   | Selection    | A selected group header drifts to another group on collapse                     | P43       |
| B31 | Medium   | Paging       | The page index isn't clamped when data shrinks, so the grid shows empty         | P87       |
| B32 | Medium   | Paging       | Grouped grids advertise pages they can't turn                                   | P38       |
| B33 | Medium   | Groups       | Group expansion leaks between grouping fields                                   | P42       |
| B34 | Medium   | Groups       | Group paths collide (`null` vs `"null"`, `1` vs `"1"`)                          | P19, P20  |
| B35 | Medium   | Groups       | Group header order ignores the column's comparator                              | P17       |
| B36 | Medium   | Groups       | The blank group jumps to the top when groups sort descending                    | P18       |
| B37 | Medium   | Groups       | `collapseAll` doesn't close groups that appear later                            | P23       |
| B38 | Medium   | Columns      | `moveColumn` uses the declaration index, not the display index                  | P33       |
| B39 | Medium   | Saved views  | `restoreState` doesn't emit `GridChange.layout`                                 | P34       |
| B40 | Medium   | Tree         | Nested trees: search, filters and sort never reach children                     | P63, P64  |
| B41 | Medium   | Async        | After a failed fetch, counts and aggregates describe rows that are gone         | P116      |
| B42 | Medium   | Filter UI    | `distinctValuesFor` misleads checkbox filter lists                              | P39–P41   |
| B43 | Medium   | Export       | Grouped CSV export indents every cell, so numbers become text                   | P54       |
| B44 | Medium   | Export       | Negative numbers are exported as `'-5`                                          | P55       |
| B45 | Medium   | Export       | Grouped export includes collapsed groups; its `expansion` parameter is unused   | P52       |
| B46 | Medium   | Clipboard    | Copied cells with newlines/tabs break rows on paste                             | P56       |
| B47 | Medium   | Clipboard    | Copying a selection with group headers emits blank rows                         | P79       |
| B48 | Medium   | Sort         | Default text sort is code-unit order (`Cherry` before `apple`)                  | P16       |
| B49 | Medium   | Compare      | `compareValues` is intransitive across mixed types; `BigInt` compares as text   | P01, P04  |
| B50 | Medium   | Editing      | Number coercion accepts hex and NaN; `numberRange` lets NaN through             | P57, P58  |

### Critical — data integrity

#### B01 · Editing one of two equal rows writes to the other

- **Where:** `data_source.dart:397` (`commit`), `:416` (`commitAll`)
- **Repro (P47):** `InMemoryDataSource([(name:'a'), (name:'a')])`, edit row 1 to `'z'`.
- **Expected** `['a','z']` · **actual** `['z','a']`.
- **Cause:** The row is located with `_rows.indexOf(original)`, which uses `==`. Records and freezed/equatable models with value equality can't be told apart, so the first match is overwritten. It is also an O(n) scan per write.
- **Fix:** Locate by `identical` first. Better, carry the source index (or `rowKey`) in `RowUpdate` so the source never has to search.

#### B02 · "Case-insensitive" filters are case-sensitive for equality and ranges

- **Where:** `compare.dart:32`, used by `filter.dart:279`
- **Repro (P05–P08):** `FilterCondition(equals, 'apple')` against `'Apple'` gives `false`. The same happens for `notEquals` (matches when it shouldn't), `isIn`, `>=`, `<=` and `between`. `caseSensitive` defaults to `false`, so this is the default behaviour.
- **Cause:** `compareValuesCaseInsensitive` breaks ties with the exact comparison (`byFold != 0 ? byFold : a.compareTo(b)`). That is correct for a total sort order and wrong for filter equality.
- **Fix:** Give filters their own fold-only comparison with no tiebreak, and keep the tiebreak version for sorting.

#### B03 · A finishing write wipes a newer pending write on the same row

- **Where:** `controller.dart:1649`
- **Repro (P49):** Against a remote source, commit `'first'`, then commit `'second'` before the first resolves. Resolve the first: the cell shows `'first'` while `'second'` is still in flight.
- **Cause:** After its refresh, `_writeAll` runs `keys.forEach(_pendingWrites.remove)` unconditionally, deleting the entry the newer write owns.
- **Fix:** Stamp pending entries with a write sequence number and remove only the entry you still own. Alternatively, serialise writes per row key.

#### B04 · A refused write is never rolled back on mutable models

- **Where:** `editing.dart:101`, `controller.dart:1651-1655`
- **Repro (P50):** The remote `onCommit` throws. Edit price 80→999: `writeError` is set, but the cell still shows 999.
- **Cause:** `EditSession.commit` runs the setter on the live row before the source has accepted the change. For a setter that mutates in place (returns `null`), rollback only removes the overlay, and the object stays mutated until some later fetch replaces it.
- **Fix:** On failure, replay `originalValue` through the setter (the `CellEdit.before` is already recorded). Alternatively, for remote sources, apply in-place setters to a copy.

#### B05 · Undo loses changes for rows not in view; a failed undo consumes history

- **Where:** `controller.dart:1831` (`undo`), `:1839` (`_replay`), `:1865` (`_currentRowFor`)
- **Repro (P46):** Paste `K2\nM2` over Keyboard and Mouse, then filter so only `M2` is visible, then undo. Mouse is restored, but Keyboard stays `K2` permanently, because the action has already moved to the redo stack.
- **Repro (P45):** Edit a row, filter it out, then undo. `undo()` returns `false`, yet `canRedo == true` and `canUndo == false`, so the edit can no longer be undone.
- **Cause:** `_currentRowFor` only scans `_visibleRows` (collapsed groups, other pages and filtered rows are invisible to it), and `takeUndo()` moves the action before knowing whether it can be applied.
- **Fix:** Resolve rows through a key index over the source, not the view. Peek, apply, then commit the history move. Report partial application instead of a bare bool.

#### B06 · Lazy groups: loads from before a filter change are shown after it

- **Where:** `controller.dart:515`, `:645-663`
- **Repro (P51):** With `lazyGrouping`, group loads are in flight. Call `setSearch('key')`, then let the loads resolve. Every pre-search row is shown: `[Laptop, Dock, Monitor, Keyboard, Mouse, Webcam]`.
- **Cause:** `_fetch` clears `_loadedGroups` but not `_loadingGroups`. `_requestOpenGroups` then skips those paths as "already loading", and `_loadGroup` only checks `source != _dataSource`, not whether the query is still current.
- **Fix:** Capture `_fetchToken` (or a query generation) in `_loadGroup` and drop mismatched answers. Clear `_loadingGroups` on a new fetch, and hand group loads a `FetchSignal` so they can be cancelled.

### High — wrong state, crashes and hangs

#### B07 · `sourceIndex` is the sorted position, not the source index

- **Where:** `rows.dart:310`, `controller.dart:727`
- **Repro (P30):** Sort by price descending. The first row reports `sourceIndex` 1, but its real source index is 4. The doc says "index of data in the unsorted, unfiltered source list". Grouped and tree rows always report `-1`, even for local data.
- **Fix:** Thread the matched indices that `_matchedFor` already caches through ordering, or rename the field to `resultIndex` and document it.

#### B08 · `setDataSource` keeps state from the old source

- **Where:** `controller.dart:2023`
- **Repro (P36):** In a lazy tree, call `setDataSource(new)`. The children loaded from the old source are still rendered.
- **By reading:** `_loadedGroups`, `_groupErrors`, `_childErrors`, `_pendingWrites`, `_openDetails` and the undo history aren't reset either. `_loadChildren` never checks which source it was started for.
- **Fix:** Reset per-source caches and bump a source generation that every in-flight loader checks.

#### B09 · `reload()` never refetches lazy tree children

- **Where:** `controller.dart:478`, `:932`
- **Repro (P35):** The server's children change, then `reload()` runs. The grid still shows `'old child'`.
- **Cause:** `_loadedChildren` is only cleared by `invalidateChildren`.
- **Fix:** Clear it on `reload()`, keeping the expansion state, and refetch the open branches.

#### B10 · Optimistic remote edits are invisible in tree and grouped views

- **Where:** `controller.dart:721`
- **Repro (P71):** A remote tree grid with a pending commit of `'edited'` still shows `'b'` until the server answers.
- **Cause:** `_substituteWrite` is only applied to the flat `LazyDataRowList` / `DetailRowList`. By reading, the grouped branch of `_rowsFor` has the same gap.
- **Fix:** Substitute pending rows in `result` before flattening, which covers every shape.

#### B11 · Date filters don't survive a saved view

- **Where:** `filter.dart:303` (`toJson`), `:312` (`fromJson`)
- **Repro (P09):** `jsonEncode(FilterCondition(value: DateTime(2024)).toJson())` throws `JsonUnsupportedObjectError`. The same is true of `GridViewState` and `GridQuery` JSON that contains it.
- **Repro (P10b):** With a `toEncodable`, the operand comes back as a `String`. `DateTime(2024,6,1,5) > '2024-06-01T00:00:00.000'` then evaluates to `false`, because `toString` and ISO strings compare differently.
- **Fix:** Use a typed operand encoding (for example `{'$date': iso}`) and decode against the column type when restoring.

#### B12 · A filter on a removed column keeps hiding every row

- **Where:** `controller.dart:1035` (`setColumns`), `:338-342` (`query`)
- **Repro (P44):** Filter `category = Input`, then call `setColumns` without `category`. The grid shows 0 rows, and there's no header left from which to clear the filter.
- **Fix:** On column changes, drop or park filters, sorts and groups whose field no longer exists, or treat unknown fields as pass-through.

#### B13 · Deep trees overflow the stack

- **Where:** `tree.dart:122` (`walk`), `:177` (`mark`)
- **Measured (P61):** An expanded parent chain overflows between 4,500 and 5,000 levels. A collapsed one survives 6,000 but overflows by 20,000, because `rootsOf.mark` recurses regardless of expansion. Folder trees and BOMs from user data can reach this depth.
- **Fix:** Use an explicit stack in `walk`, `mark` and `collectTreePaths`.

#### B14 · `dispose()` leaves a debounced refresh future pending forever

- **Where:** `controller.dart:2033`
- **Repro (P37):** Call `refresh(coalesce: true)` and then `dispose()`. The returned future never completes, so callers awaiting it hang and tests leak.
- **Fix:** Complete `_debounced` in `dispose`.

#### B15 · A direct refresh orphans an in-flight coalesced refresh

- **Where:** `controller.dart:408-410`
- **Repro (P121):** `final f = refresh(coalesce: true); await refresh();` leaves `f` uncompleted forever.
- **Cause:** The non-coalesced path cancels the timer but leaves `_debounced` uncompleted.
- **Fix:** Complete or chain `_debounced` onto the direct fetch.

#### B16 · A source that throws `FetchCancelled` leaves `isLoading` stuck at `true`

- **Where:** `controller.dart:518-521`
- **Repro (P119):** A source maps an aborted HTTP call to `FetchCancelled`, and the spinner never stops.
- **Cause:** The handler assumes the grid cancelled the fetch and that a newer fetch owns the state.
- **Fix:** Swallow the exception only when `token != _fetchToken` or the signal is actually cancelled. Otherwise reset `_loading` and surface it as an error.

#### B17 · One malformed entry makes `GridViewState.fromJson` throw

- **Where:** `view_state.dart:143`, `sort.dart:49`, `filter.dart:312`
- **Repro (P65):** `{'sorts':[{'dir':'descending'}]}` throws `TypeError: Null check operator`. The doc promises "missing ones take their defaults … rather than throwing", so one corrupt saved view crashes restore.
- **Repro (P113):** An `isIn` condition whose value isn't a list throws `TypeError` from `isEmpty`.
- **Fix:** Parse tolerantly: skip invalid entries and collect warnings. Throw `FormatException` rather than `TypeError`.

#### B18 · Grouped export with zero columns throws `RangeError`

- **Where:** `export.dart:116`
- **Repro (P53):** `ExportOptions(fields: [])` with grouping fails at `List.filled(exported.length - 1, '')`, i.e. a length of −1.
- **Fix:** Guard the empty case.

### High — performance cliffs

#### B19 · `isIn` is O(rows × values)

- **Where:** `filter.dart:266`
- **Measured (PF3):** At 50k rows, 1,000 values take 1,920 ms, against 39 ms for 10 values. A checkbox filter list produces exactly these sets.
- **Fix:** Build a normalised `HashSet` once per condition: case-folded for text, numeric for numbers.

#### B20 · `compareValuesNatural` is 45× slower than the default sort

- **Where:** `compare.dart:39-55`
- **Measured (PF2):** Sorting 50k codes takes 53 ms by default and 2,405 ms with the natural comparator.
- **Cause:** A `RegExp` is constructed, and both strings are tokenised into lists, on every comparison.
- **Fix:** Hoist the RegExp, or better, compute a chunked key once per row (see A02).

#### B21 · Conditional formatting eats 13.5 ms of the frame on a wide grid

- **Where:** `controller.dart:1479` → `:253`, and `data_source.dart:562-563`
- **Measured (PF13):** `decorationFor` over 40 rows × 200 columns takes 13.48 ms.
- **Cause:** Every call does a linear `column(field)` scan and builds a `'$revision\u0000$_matchedKey'` string in `statsFor`.
- **Fix:** Cache a field→column map in the controller and use an integer stats generation instead of string keys.

#### B22 · Tree paths grow quadratically with depth

- **Where:** `tree.dart:126`
- **Measured (PF9):**

  | Chain depth | Total path characters | Flatten time |
  | ----------- | --------------------- | ------------ |
  | 1,000       | 1.9M                  | 11 ms        |
  | 2,000       | 8.3M                  | 40 ms        |
  | 4,000       | 36M                   | 110 ms       |

- **Cause:** Every row's path repeats all of its ancestors' keys.
- **Fix:** Key tree expansion by `rowKey` (keys are already unique within a tree), or intern `(parentId, key)` pairs.

#### B23 · Infinite scroll re-downloads everything on each `loadMore`

- **Where:** `controller.dart:361-368`, `:448`
- **Measured (PF10):** Ten slices of 100 rows transfer 5,500 rows to show 1,000. That is O(n²) against a remote API.
- **Fix:** Append `offset = loaded, limit = slice`, and reset only when the query changes.

### Medium — performance

#### B24 · The README's "~100k rows inside a frame budget" claim is not met

- **Where:** `README.md:207-208`
- **Measured (PF1):**

  | Operation               | 50k rows | 100k rows |
  | ----------------------- | -------- | --------- |
  | Sort by one text column | 25 ms    | 53 ms     |
  | Sort by three columns   | 32 ms    | 65 ms     |
  | First search keystroke  | 29 ms    | 50 ms     |

  Your own benchmark already reports the three-column sort over budget at 50k.

- **Fix:** Either the work in A01/A04/A05, or restate the claim (around 20k on this hardware).

#### B25 · Editing one cell invalidates every pipeline cache

- **Where:** `data_source.dart:379` (`replaceAt` → `bumpRevision`)
- **Measured (PF5):** One commit with a search and a sort active costs 55 ms at 50k: a full re-index, re-filter and re-sort.
- **Fix:** Row-level revisions (A04).

#### B26 · A group toggle rebuilds the whole flat list

- **Where:** `controller.dart:917`, `rows.dart:231`
- **Measured (PF16):** 36 ms at 200k rows.
- **Fix:** A lazy grouped row list (A07).

#### B27 · Select-all is O(n) everywhere

- **Where:** `selection.dart:239`, `:131`, `controller.dart:751`
- **Measured (PF11, PF7):**
  - `selectAllRows` on 1M rows takes 109 ms to build a 1M-entry `Set`.
  - `selectedRows` sorts a fresh copy on every read: 7 ms at 50k.
  - A re-sort with every row selected and a `rowKey` takes 72 ms, against 25 ms with nothing selected.
- **Fix:** A range or inverted-set selection (A09).

#### B28 · `scrollableRows` and the frozen bands materialise every lazy row

- **Where:** `controller.dart:1432-1443`
- **Measured (PF6):** 4.5 ms per read at 50k, because `sublist` over `LazyDataRowList` builds 50k `DataGridRow` objects.
- **Fix:** Return an offset view instead of a copy.

### Medium — selection, paging, grouping, columns

#### B29 · A cell range outlives the rows it covered

- **Where:** `selection.dart:298` (`clampTo`)
- **Repro (P32):** A range over rows 0..5, then a filter down to 2 rows. `range.lastRow` is still 5, and `copySelectionAsText` emits rows that no longer exist.
- **Fix:** Clamp or drop `_anchor` and `_range`, not just `_activeCell`.

#### B30 · A selected group header drifts to another group on collapse

- **Where:** `controller.dart:546`
- **Repro (P43):** Select the `Display` header and collapse `Compute`. The selection is now on `Input`, even though a `rowKey` is set.
- **Cause:** Headers keep their raw index during remapping.
- **Fix:** Track headers by `GroupGridRow.path` in `_trackedRowKeys`.

#### B31 · The page index isn't clamped when data shrinks

- **Where:** `controller.dart:304`, `:531`
- **Repro (P87):** Go to page 3 of 3, then remove rows. The grid ends up with `pageIndex` 2 and `pageCount` 1, and shows nothing although rows exist.
- **Fix:** Clamp in `_apply`.

#### B32 · Grouped grids advertise pages they can't turn

- **Where:** `controller.dart:304`, `:361-365`
- **Repro (P38):** With groups and `pageSize: 2`, `pageCount` is 3, but `nextPage()` shows the same rows.
- **Fix:** Report `pageCount` as 1 while grouped, or implement group paging.

#### B33 · Group expansion leaks between grouping fields

- **Where:** `group.dart:265`
- **Repro (P42):** Collapse the `x = true` group, then regroup by `y`. The `y = true` group starts collapsed.
- **Cause:** The path holds key values without their field.
- **Fix:** Use `field=key` segments.

#### B34 · Group paths collide

- **Where:** `group.dart:265`
- **Repro (P19, P20):** A `null` group and a `"null"` group get the same path, as do `1` and `"1"`. The colliding groups share expansion state and the lazy-load cache.
- **Fix:** Use type-tagged, escaped path segments.

#### B35 · Group header order ignores the column's comparator

- **Where:** `group.dart:256`
- **Repro (P17):** Priority groups `High / Medium / Low` sort to `High, Low, Medium`, even though the sort itself respects the comparator.
- **Fix:** Use `column.comparator` for group keys when no `keyOf` is set.

#### B36 · The blank group jumps to the top when groups sort descending

- **Where:** `group.dart:256`
- **Repro (P18):** Sorting treats null placement as absolute, but grouping flips it with the direction.
- **Fix:** Handle nulls before applying direction, and add `GroupSpec.nulls`.

#### B37 · `collapseAll` doesn't close groups that appear later

- **Where:** `rows.dart:218`
- **Repro (P23):** The doc says it "closes every group, including ones not yet seen". That's false when `expandedByDefault` is true, because only the known paths are added. `collapseAllRows` has the same problem.
- **Fix:** Flip the default mode and clear the overrides, instead of enumerating paths.

#### B38 · `moveColumn` uses the declaration index, not the display index

- **Where:** `controller.dart:1158`
- **Repro (P33):** With a hidden column present, `moveColumn('a', 2)` lands at display position 1, although the doc says display order. Pinned bands cause the same drift.
- **Fix:** Translate the display index to a list index.

#### B39 · `restoreState` doesn't emit `GridChange.layout`

- **Where:** `controller.dart:1979`
- **Repro (P34):** Restoring widths, order and pins notifies only `rows`, `selection` and `status`. Adapters that relayout on `layout` keep the old geometry.
- **Fix:** Batch the restore and add a layout notification, as `setColumns` does.

#### B40 · Nested trees: search, filters and sort never reach children

- **Where:** `tree.dart:107`, and the source pipeline
- **Repro (P63):** Searching for a child's name returns 0 rows.
- **Repro (P64):** Sorting by name leaves the children unsorted.
- **Fix:** Flatten the nested model into `(row, parent)` pairs before the pipeline, or filter and sort inside `flattenTree` while keeping ancestors.

#### B41 · After a failed fetch, counts and aggregates describe rows that are gone

- **Where:** `controller.dart:522-528`
- **Repro (P116):** The grid has 0 rows but `matchedCount` is 6, so the footer and aggregates show stale numbers.
- **Fix:** Clear `_result`, or expose `isStale`, when `keepRowsOnError` is false.

#### B42 · `distinctValuesFor` misleads checkbox filter lists

- **Where:** `data_source.dart:590-616`
- **P39:** A truncated list is the same length as a complete one. The comment says it is "one over the limit, so a caller can tell", but it is then cut back to `limit`.
- **P40:** The truncated list holds the first values seen, not the smallest (it gave `v0, v7, v8`).
- **P41:** The list is narrowed by the column's own filter. Pick `Input` and the list offers only `Input`, so other values can never be added.
- **Fix:** Return `(values, truncated)`, select the smallest values, and compute over the rows that match every filter except the column's own.

### Medium — export and clipboard

#### B43 · Grouped CSV export indents every cell

- **Where:** `export.dart:122`
- **Repro (P54):** The price is exported as `"    1450"`, so spreadsheets read numbers as text and sums break.
- **Fix:** Indent only the first column, or emit a level column instead.

#### B44 · Negative numbers are exported as `'-5`

- **Where:** `export.dart:166`
- **Repro (P55):** The formula sanitiser treats a leading `-` as a formula, so every negative number in a numeric column becomes text.
- **Fix:** Skip values that parse as plain numbers, or skip `ColumnType.number` columns.

#### B45 · Grouped export includes collapsed groups

- **Where:** `export.dart:103`, `:136`
- **Repro (P52):** The `expansion` parameter is accepted and never read. `exportCsv` documents itself as "matching what is on screen".
- **Fix:** Honour expansion (or add `ExportOptions.respectCollapsed`), or drop the parameter.

#### B46 · Copied cells with newlines or tabs break rows on paste

- **Where:** `export.dart:251` (`toClipboardText`), `:232` (`parseClipboardText`)
- **Repro (P56):** One cell containing `line1\nline2` pastes back as 2 rows. Excel and Sheets quote such cells, and the parser doesn't read quotes either.
- **Fix:** Quote cells containing `\t`, `\n`, `\r` or `"`, and parse quoted fields.

#### B47 · Copying a selection with group headers emits blank rows

- **Where:** `controller.dart:1903-1913`
- **Repro (P79):** Select a header and a data row, then copy. A row of empty tabs leads the clipboard text.
- **Fix:** Skip non-data rows, or write the header label.

### Medium — sorting, comparison, coercion

#### B48 · Default text sort is code-unit order

- **Where:** `sort.dart:174`, `compare.dart:15`
- **Repro (P16):** `[banana, Cherry, apple]` sorts to `[Cherry, apple, banana]`. Accented characters also sort after `z`.
- **Fix:** Default `ColumnType.text` to a case-folded order with an exact tiebreak, computed as keys once per row (A01/A02) so the fast path stays fast.

#### B49 · `compareValues` is intransitive across mixed types

- **Where:** `compare.dart:24`
- **Repro (P01):** `9 < 10` numerically, `10 < "5"` as strings, and `"5" < 9` as strings form a cycle. That breaks `List.sort`'s contract, so mixed columns can order differently between runs, and min/max depend on input order.
- **Repro (P04):** `BigInt(10)` sorts below `9`.
- **Fix:** Rank by type class first (null, bool, num/BigInt, DateTime, String, other), then compare within the type.

#### B50 · Number coercion accepts hex and NaN; `numberRange` lets NaN through

- **Where:** `editing.dart:122`, `:146`
- **Repro (P57):** `coerceValue('0x10', number)` returns 16, and `'NaN'` returns `NaN`.
- **Repro (P58):** `numberRange(min:0, max:10)(double.nan)` returns `null`, i.e. valid. Pasting "NaN" therefore passes validation and poisons sums and sorts.
- **Fix:** Accept decimal input only, and reject non-finite values in both places.

### Also confirmed (lower priority)

These failed their probes too, but rank below the top 50.

| Probe    | Issue                                                                                                                                                                                                                                                               | Where                                |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| P02      | `compareValuesCaseInsensitive` doc says "accent-insensitive"; it only lowercases (`école` > `zebra`)                                                                                                                                                                | `compare.dart:27-35`                 |
| P03      | `compareValuesNatural` misorders digit runs beyond int64 (falls back to text compare)                                                                                                                                                                               | `compare.dart:47`                    |
| P13      | `between` with reversed bounds matches nothing                                                                                                                                                                                                                      | `filter.dart` (between)              |
| P14      | `equals` on a date column needs the exact instant; no date-only mode                                                                                                                                                                                                | `filter.dart`                        |
| P15      | Operands aren't coerced to the column type: a number filter given `'50'` compares as text                                                                                                                                                                           | `filter.dart:279`                    |
| P21, P22 | `GroupSpec`/`Aggregation` fingerprints and `==` use closure identity. The doc's claim that "closures written at the same place … are `==` in Dart" is false, so an inline `keyOf` misses the cache on every rebuild (only ~2 ms at 50k per PF12, but `==` is wrong) | `group.dart:53`, `aggregate.dart:78` |
| P24, P25 | `countDistinct` counts null; `sum`/`average` parse `'NaN'`/`'Infinity'` text into NaN                                                                                                                                                                               | `aggregate.dart:110`, `:138`         |
| P26      | Average of −0.001 formats as `-0.00`                                                                                                                                                                                                                                | `aggregate.dart` (`formatted`)       |
| P27, P28 | `GridColumn.copyWith` can't clear nullable fields (you can't make a column read-only); the default Map getter keeps the old field after `copyWith(field:)`                                                                                                          | `column.dart:143`, `:192`            |
| P29, P76 | One throwing listener stops every listener after it                                                                                                                                                                                                                 | `notifier.dart:107`, `fetch.dart:83` |
| P48      | Committing an unchanged value still writes to the server and refetches                                                                                                                                                                                              | `controller.dart:1556`               |
| P66      | A paste across a group header drops a row instead of skipping to the next data row                                                                                                                                                                                  | `controller.dart:1678`               |
| P67      | Duplicate column fields are accepted silently (`columnsByField` drops one)                                                                                                                                                                                          | constructor                          |
| P68      | `stackedHeaders` passed to the constructor skip validation (the setter validates)                                                                                                                                                                                   | `controller.dart:62`                 |
| P60      | `ColumnFit.stretch` dumps the clamped remainder on the last column: `[110, 200, 290]` instead of `[110, 245, 245]`                                                                                                                                                  | `layout.dart:183`                    |
| P31      | `DetailRowList` returns a phantom detail row for an out-of-range index instead of throwing `RangeError`                                                                                                                                                             | `rows.dart:425`                      |
| P69      | `moveToNextEditableCell` walks into cells on a read-only source                                                                                                                                                                                                     | `controller.dart:1332`               |
| P72      | `CellRange.contains` disagrees with `coveredFields` when a field disappears                                                                                                                                                                                         | `selection.dart`                     |
| P82      | Humanised titles don't split acronyms (`HTTPStatus`)                                                                                                                                                                                                                | `column.dart:203`                    |
| P85      | `ColumnStats.mean` divides by a count that includes non-numeric values (`[10,'n/a']` gives 5)                                                                                                                                                                       | `decoration.dart:117`                |
| P11, P12 | `isIn` conditions and `FilterGroup` lack value equality                                                                                                                                                                                                             | `filter.dart`                        |

### Ruled out (tested, behaved correctly)

- **P59:** One NaN in a column does not break `DataBarRule`.
- **P122:** A hidden column is correctly excluded from search.
- **PF8 / PF15:** Undoing or pasting 1,000 rows at the top of 50k takes 39 ms / 1.4 ms. Acceptable, although both scans are O(n) per row and degrade for rows near the bottom.

---

## Part 2 — Top 50 additions

These are new capabilities rather than bug fixes. Where one also removes a bug above, it says so. Effort: **S** ≈ days, **M** ≈ 1–2 weeks, **L** ≈ a release.

### Performance (A01–A17)

| #   | Addition                                                                                                                                                                             | Why / evidence                                                                                                        | Where                          | Effort |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- | ------------------------------ | ------ |
| A01 | **Typed, precomputed sort keys.** `Float64List` for numbers, folded strings for text, an `Int32List` permutation, and merge/radix for multiple columns.                              | 3-column sort at 50k is 32–35 ms against a 16.7 ms budget (B24). It also makes a case-folded default sort free (B48). | `sort.dart`                    | M      |
| A02 | **`GridColumn.sortKey`** transform, computed once per row per sort (natural order, collation, enum rank).                                                                            | Replaces per-comparison work. Fixes B20 (45×) and B35.                                                                | `column.dart`, `sort.dart`     | S      |
| A03 | **Compiled filters.** Compile the filter tree once per query: pre-folded needles, `HashSet` for `isIn`, operands coerced to the column type.                                         | `contains` lowercases the needle on every row; `isIn` is linear (B19); operands aren't coerced (P15).                 | `filter.dart`                  | M      |
| A04 | **Row-level revisions** in `InMemoryDataSource`: `replaceAt` records dirty indices, and each stage patches (re-index one row, re-test one row, binary re-insert).                    | One edit costs 55 ms at 50k (B25).                                                                                    | `data_source.dart`             | L      |
| A05 | **Columnar value cache.** Read each accessor once per revision into typed columns shared by filter, sort, stats, aggregates and search.                                              | Accessors are re-run by every stage; this is the base for A01/A03.                                                    | `data_source.dart`             | L      |
| A06 | **Background execution** with `Isolate.run` for sort, group and export over a threshold, returning a permutation and honouring `FetchSignal`.                                        | Keeps 100k+ interactions off the UI thread on native.                                                                 | new `compute.dart`             | M      |
| A07 | **Lazy grouped row list**: a group tree with visible subtree sizes, O(log G) index→row and an O(depth) toggle.                                                                       | A toggle costs 36 ms at 200k (B26).                                                                                   | `rows.dart`                    | M      |
| A08 | **Aggregate roll-up**: compute leaves once and merge upward (sum, count, min, max; avg as sum/count), one pass per field for every aggregate.                                        | Today each level and each aggregate re-reads the same values.                                                         | `group.dart`, `aggregate.dart` | M      |
| A09 | **Range/inverted selection model**: O(1) select-all, remap per range.                                                                                                                | Select-all is 109 ms at 1M; `selectedRows` 7 ms per read (B27).                                                       | `selection.dart`               | M      |
| A10 | **Shared key index per result** (`key → position`, built once) reused by selection remap, undo, detail panels and pending writes.                                                    | Several O(n) scans per refresh today. Underpins B05's fix.                                                            | `controller.dart`              | S      |
| A11 | **Fenwick-tree `RowMetrics` on `Float64List`**: O(log n) height updates, around 3× less memory than boxed `List<double>`.                                                            | 1M build is 57 ms, and any height change rebuilds everything (PF18).                                                  | `virtualization.dart`          | M      |
| A12 | **Streaming CSV export**: `Stream<String>` in chunks, cancellable.                                                                                                                   | A 50k export builds one giant string.                                                                                 | `export.dart`                  | S      |
| A13 | **Remote page cache and prefetch**: an LRU of results keyed by query fingerprint, plus next-page and next-slice prefetch.                                                            | Back/forward paging becomes instant, with no round trip for pages already seen.                                       | `controller.dart`              | M      |
| A14 | **Search index v2**: tokenised multi-term AND search (`john sales`), accent folding, prefix index.                                                                                   | Today the whole needle must match inside one column.                                                                  | `data_source.dart`             | M      |
| A15 | **Flyweight rows**: reuse `DataGridRow` wrappers per index and generation instead of allocating on every read.                                                                       | `LazyDataRowList` allocates per read, and adapters read rows several times per frame.                                 | `rows.dart`                    | S      |
| A16 | **Benchmark gate v2**: add the PF probes from this report (isIn 1k, natural sort, 200-column decoration, tree depth 4k, toggle at 200k, infinite-scroll transfer, edit with search). | The current gate missed every cliff in B19–B28.                                                                       | `benchmark/`                   | S      |
| A17 | **Incremental tree flattening**: cache the flattened tree per expansion generation and splice only the toggled subtree.                                                              | Each toggle re-walks the whole tree today.                                                                            | `tree.dart`                    | M      |

### UI-facing engine APIs (A18–A34)

| #   | Addition                                                                                                                                                                                       | Why                                                                              | Where                 | Effort |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | --------------------- | ------ |
| A18 | **Command layer and default keymap**: a `GridCommand` enum (copy, paste, fillDown, selectAll, beginEdit, cancel, toggleGroup, undo, …) with platform bindings.                                 | Every adapter re-implements key handling and drifts.                             | new `commands.dart`   | M      |
| A19 | **Accessibility descriptors**: engine-produced labels and announcements ("row 5 of 200", sort state, "12 rows match", edit errors) and ARIA indices for header bands.                          | Screen-reader support is the same logic in every adapter.                        | new `a11y.dart`       | M      |
| A20 | **Edit policies**: `EditPolicy` (commit or cancel on blur), behaviour when `beginEdit` is called mid-edit (today it silently discards the half-typed value), Enter/Tab direction after commit. | Spreadsheet users expect commit-on-move.                                         | `controller.dart`     | S      |
| A21 | **Editor hints on columns**: `options` (enum values), `editorKind`, a `parse`/`format` pair, min/max/step.                                                                                     | Adapters pick editor widgets from engine data instead of guessing.               | `column.dart`         | S      |
| A22 | **Fill handle and fill-down**: series detection (1,2,3 / Mon,Tue / dates), copy-down, fill into a range, one undo step.                                                                        | A core spreadsheet gesture with no engine support.                               | `controller.dart`     | M      |
| A23 | **Paste-to-fill and paste-to-append**: a single value fills the selection; overflow rows go to an `onPasteNewRows` callback that creates `T`.                                                  | Today extra rows are only counted as clipped.                                    | `controller.dart`     | S      |
| A24 | **Multi-range selection** (ctrl-drag) with a rectangular check on copy.                                                                                                                        | Only a single range exists today.                                                | `selection.dart`      | M      |
| A25 | **Column sizing modes**: `flex` weights, `ColumnFit.shrink`, water-filling distribution (fixes P60), auto-unpin when pinned panes exceed the viewport.                                         | Pinned panes wider than the viewport leave no scroll area.                       | `layout.dart`         | S      |
| A26 | **Collapsible column groups** (`HeaderBand.collapsible` with a summary column) and nested band validation (an inner band must sit inside one outer band).                                      | Wide financial grids need to fold quarters into a year.                          | `stacked_header.dart` | M      |
| A27 | **Group footer/subtotal rows** (`GroupFooterGridRow`), aggregate placement (header, footer, both), and footer line-count metadata so adapters size footers.                                    | The demo's footer overflowed by 13 px with 3 aggregates on one column.           | `rows.dart`           | M      |
| A28 | **Search highlight spans**: per-cell match ranges from the search index.                                                                                                                       | Every adapter re-searches the text to highlight it.                              | `data_source.dart`    | S      |
| A29 | **Tree filter modes**: keep ancestors of matches (`isMatch` / `isAncestorOfMatch` flags) and auto-expand to matches.                                                                           | Today a matching child is shown as an orphan root.                               | `tree.dart`           | M      |
| A30 | **Row pinning by identity** (pin row X to the top) alongside positional frozen rows.                                                                                                           | "Pin my totals or favourites" can't be built today.                              | `controller.dart`     | S      |
| A31 | **Column menu model**: the engine returns the available actions per column with enabled state derived from capabilities.                                                                       | Menus drift between adapters.                                                    | `controller.dart`     | S      |
| A32 | **Localisation interface**: `LatticeStrings` for the blank label, operator labels, the export `(n)` suffix, aggregate labels and messages.                                                     | `blankLabel` is the only hook; the rest is hard-coded English.                   | new `strings.dart`    | S      |
| A33 | **Typed event stream**: `Stream<GridEvent>` (Sorted, Filtered, CellEdited, WriteFailed, PasteRejected, Exported).                                                                              | Toasts, analytics and undo UI need _what happened_, not just a `GridChange` set. | `notifier.dart`       | S      |
| A34 | **View history**: undo/redo for sort, filter, column move and resize, separate from data history.                                                                                              | Users undo layout mistakes too.                                                  | `history.dart`        | M      |

### Specialisations (A35–A50)

| #   | Addition                                                                                                                                                               | Why                                                                                                 | Where              | Effort |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------ | ------ |
| A35 | **Pivot mode**: row groups × column-pivot values with aggregate cells, generated columns and totals.                                                                   | The most requested enterprise grid feature, and the grouping and aggregation engines already exist. | new `pivot.dart`   | L      |
| A36 | **Server query translators**: `GridQuery` → parameterised SQL (dialects), REST query string, OData/GraphQL variables.                                                  | Every `AsyncDataSource` user writes this, often unsafely.                                           | new `translate/`   | M      |
| A37 | **Master–detail with nested controllers**: `DetailGridRow` carries a child grid spec with lazy data keyed by `rowKey`.                                                 | Detail panels exist, but nested grids are hand-built.                                               | `rows.dart`        | M      |
| A38 | **Live/streaming mode**: upsert and remove by `rowKey` with batched coalescing, changed-cell flash metadata, throttled re-sort, and a pause-sort-while-editing option. | Trading and monitoring grids; today each update is a full refresh.                                  | `data_source.dart` | L      |
| A39 | **Computed columns with dependencies**: `compute(row, read)`, memoised per revision and invalidated when inputs are edited.                                            | Totals and margins without model changes.                                                           | `column.dart`      | M      |
| A40 | **Richer conditional formatting**: row-level rules, top/bottom-N, duplicate/unique, icon sets, diverging bars around zero, midpoint as a value.                        | `DataBarRule` can't show negatives; `ColorScaleRule`'s midpoint is a fraction.                      | `decoration.dart`  | M      |
| A41 | **Faceted filtering**: distinct values with counts excluding the column's own filter, date hierarchies (year → month → day), numeric histogram buckets.                | Builds on the B42 fix.                                                                              | `data_source.dart` | M      |
| A42 | **Relative date filters**: serialisable tokens (`today`, `last7Days`, `thisQuarter`) resolved at evaluation time, timezone-aware, with a date-only column mode.        | Saved views with fixed dates go stale (see also P14).                                               | `filter.dart`      | S      |
| A43 | **XLSX export** (pure Dart): typed cells, number formats, frozen panes, outline levels for groups, autofilter; plus JSON/NDJSON.                                       | CSV loses types, which is where B43/B44 came from.                                                  | new `xlsx.dart`    | L      |
| A44 | **Validation schema**: allowed values, regex, cross-field row validators, and async validators (uniqueness) with a pending state.                                      | Only per-cell sync validators exist.                                                                | `editing.dart`     | M      |
| A45 | **Change tracking**: dirty cells per row, original values, "save all" / "revert row", batch commit with per-row results, version/ETag conflict detection.              | Form-style editing over a remote API.                                                               | `controller.dart`  | M      |
| A46 | **Tree aggregation**: parent rows show the sum/avg of their descendants.                                                                                               | Org charts and bills of materials.                                                                  | `tree.dart`        | S      |
| A47 | **Locale-aware formatters and parsers** (currency, percent, accounting negatives, separators) used consistently by display, paste and filter input.                    | `coerceValue` rejects `1,234.50` today.                                                             | new `format.dart`  | M      |
| A48 | **Row drag-reorder** with a manual order persisted in `GridViewState` (when unsorted).                                                                                 | Priority lists and playlists.                                                                       | `controller.dart`  | S      |
| A49 | **Fuzzy search option**: typo tolerance with ranked results.                                                                                                           | Large people and product lists.                                                                     | `data_source.dart` | M      |
| A50 | **Sparkline cell data**: per-row series stats (min, max, last, trend) from list-valued columns.                                                                        | Chart-in-cell without adapter maths.                                                                | `decoration.dart`  | S      |

---

## Suggested order

1. **B01–B06.** Data-integrity bugs users can't detect themselves.
2. **B13–B18.** Crashes and hangs; B14 and B15 also make async tests flaky.
3. **B19–B23.** Performance cliffs, together with A16 so they stay fixed.
4. **The remaining bugs**, then A01–A05. Those five additions lift every interaction at 50k+ and retire B24 and B25.

## Appendix — found in the demo app, not the engine

From running every demo page in widget tests (12 pages, shell navigation, 900×700 window):

- **Filtering page:** the Field/Operator dropdowns overflow by 81 px and 91 px at ~97 px wide (`lib/src/pages/filtering_page.dart:374`, `:400`).
- **Grouping page:** the footer cell overflows by 13 px when one column has 2+ aggregates (`lib/src/adapter/lattice_grid.dart:1174`). This motivates A27's footer metadata.
- **Grouping / Formatting / Export pages:** `DemoPanel` is an opaque `Container` without a `Material`, so every `SwitchListTile`/`CheckboxListTile` inside it loses its ink and trips Flutter's assertion (`lib/src/widgets/demo_page.dart:255`).
- **Shell:** overflows 138 px vertically at 900×700; there is no layout below desktop size.
