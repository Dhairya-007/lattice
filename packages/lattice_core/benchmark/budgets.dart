/// Ceilings the benchmark is allowed to reach, in milliseconds.
///
/// These are a regression gate, not a target. A number here is what an
/// operation may cost before CI treats it as a defect.
///
/// Each one is **two and a half times the slower of two machines**, with a
/// floor of 2 ms so that an operation measured in hundredths is not gated on
/// noise. That multiple is a judgement: a median of seven runs is stable to
/// well within it, so a real regression of 2x or more is caught, while the
/// ordinary variance of a shared runner is not. A tighter gate would go off
/// at random, and a gate that goes off at random is one people learn to
/// ignore.
///
/// The two machines, both medians of seven runs on 2026-11-14:
///
/// - `local` - an Apple M-series laptop, Dart 3.13.
/// - `ci` - a GitHub-hosted ubuntu-latest runner, which is *faster* than the
///   laptop at sorting and slower at building row metrics. Keeping both
///   figures is the point: a ceiling set from one machine is a ceiling nobody
///   else can interpret.
///
/// They are checked in so that a change in what the engine costs is a change
/// to a reviewed file rather than a number nobody wrote down. When an
/// operation legitimately gets slower, raise its ceiling in the same pull
/// request and say why.
///
/// The probes added in 0.4.0 are the cliffs this gate missed. Every one of
/// them was reachable by ordinary use and cost orders of magnitude more than
/// the table above suggested, which is the argument for measuring the shapes
/// a user reaches rather than the ones that are easy to measure: a filter
/// over a thousand checkbox values, a natural sort, a wide grid's
/// conditional formatting, a deep tree, a select-all followed by a re-sort,
/// and an edit with a search and a sort active. Their figures are from a
/// third machine (`m4`, an Apple M4 laptop, Dart 3.13), noted per line.
library;

/// Ceiling per operation, keyed by the row count it was measured at.
///
/// A probe whose cost does not depend on the row count is keyed by 0; see
/// [fixedShapeCeilings], which is folded in below.
const Map<String, Map<int, double>> benchmarkCeilings = {
  ...fixedShapeCeilings,
  // local 0.05 / 0.35 · ci 0.05 / 0.53
  'first load (no sort, no filter)': {10000: 2, 50000: 2},
  // local 4.50 / 27.51 · ci 2.89 / 16.89
  'sort by one column': {10000: 12, 50000: 70},
  // local 8.56 / 54.25 · ci 5.24 / 38.60
  'sort by three columns': {10000: 22, 50000: 140},
  // local 1.77 / 5.19 · ci 2.23 / 3.38
  'filter one column': {10000: 6, 50000: 14},
  // local 3.30 / 16.95 · ci 2.57 / 13.04
  'search across every column': {10000: 9, 50000: 44},
  // local 1.11 / 6.19 · ci 0.82 / 5.15
  'search, per keystroke while typing': {10000: 4, 50000: 16},
  // local 0.02 / 0.01 · ci 0.01 / 0.01
  'page change, 100 rows a page': {10000: 2, 50000: 2},
  // local 0.23 / 1.82 · ci 0.69 / 1.55
  'group by one column, with 3 aggregates': {10000: 2, 50000: 5},
  // local 0.38 / 4.41 · ci 0.30 / 8.84
  'toggle a group open and shut': {10000: 2, 50000: 23},
  // local 19.45 / 69.19 · ci 11.38 / 49.77
  'export the whole view to CSV (bulk)': {10000: 50, 50000: 180},
  // local 0.30 / 0.11 · ci 0.31 / 0.12
  'scroll window lookup x1000': {10000: 2, 50000: 2},
  // local 0.16 / 0.85 · ci 0.42 / 0.81
  'variable row metrics build': {10000: 2, 50000: 3},

  // -- Added in 0.4.0 -------------------------------------------------------

  // m4 1.90 / 6.20. Before compiled filters this was 1,920 ms at 50k: the
  // condition walked every selected value for every row.
  'isIn filter, 1000 values': {10000: 5, 50000: 16},
  // m4 9.06 / 46.35. Before the sort key it was 2,405 ms at 50k, built a
  // RegExp per comparison, and was 45x the default sort.
  'natural sort by one column': {10000: 25, 50000: 120},
  // m4 16.86 / 88.35. The one cliff 0.4.0 does not fix: a single commit
  // invalidates the whole pipeline, so the grid re-indexes, re-filters and
  // re-sorts for one changed cell. Row-level revisions are the fix, and they
  // are a release of their own. The ceiling is here so the cost cannot grow
  // unnoticed in the meantime.
  'edit one cell with a search and a sort active': {10000: 45, 50000: 230},
  // m4 4.32 / 26.64, with every row selected. Select-all itself is now O(1) -
  // it was 109 ms at 1M building a set of every index - and the re-sort that
  // follows it no longer has a selected row to remap per row.
  'select all, then re-sort': {10000: 12, 50000: 70},
  // m4 0.14 / 0.04. A band is a view onto the visible rows; copying one
  // materialised every lazy row behind it, 4.5 ms per read at 50k.
  'read the scrollable band x100': {10000: 2, 50000: 2},
};

/// Ceilings for the probes whose cost does not depend on the row count.
///
/// Stored under size 0 in [benchmarkCeilings] so the check reads them the
/// same way; kept here as its own note because the shapes are fixed.
const Map<String, Map<int, double>> fixedShapeCeilings = {
  // m4 1.19. Was 13.48 ms - 80% of a frame - because every call scanned the
  // column list and built a cache key string.
  'conditional formatting, 40 rows x 200 columns': {0: 5},
  // m4 2.36. Was 110 ms, and overflowed the stack past ~4,500 levels.
  'flatten a 4000-deep tree': {0: 12},
};
