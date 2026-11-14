/// Ceilings the benchmark is allowed to reach, in milliseconds.
///
/// These are a regression gate, not a target. A number here is what the
/// operation may cost before CI treats it as a defect, and it is set well
/// above what the code actually does, because the machine CI runs on is
/// shared, variable, and slower than a developer's: a tight budget would
/// make the build flaky, which teaches people to ignore it.
///
/// They are checked in so that a change in what the engine costs is a change
/// in a reviewed file rather than a number nobody wrote down. When an
/// operation legitimately gets slower - a feature that earns its cost - raise
/// its ceiling in the same pull request and say why.
///
/// Measured on an Apple M-series laptop, Dart 3.13, 2026-11-14, as the median
/// of seven runs; the local figures are in the comment beside each ceiling
/// for the sake of anyone wondering how much headroom there is.
library;

/// Ceiling per operation, keyed by the row count it was measured at.
const Map<String, Map<int, double>> benchmarkCeilings = {
  // local: 0.06 / 0.35
  'first load (no sort, no filter)': {10000: 4, 50000: 12},
  // local: 4.5 / 27.6
  'sort by one column': {10000: 25, 50000: 140},
  // local: 8.6 / 54.3
  'sort by three columns': {10000: 45, 50000: 260},
  // local: 1.8 / 5.3
  'filter one column': {10000: 14, 50000: 40},
  // local: 3.5 / 17.8
  'search across every column': {10000: 24, 50000: 100},
  // local: 1.2 / 6.3
  'search, per keystroke while typing': {10000: 12, 50000: 40},
  // local: 0.01 / 0.01
  'page change, 100 rows a page': {10000: 2, 50000: 2},
  // local: 0.2 / 1.4
  'group by one column, with 3 aggregates': {10000: 8, 50000: 20},
  // local: 0.4 / 5.1
  'toggle a group open and shut': {10000: 10, 50000: 40},
  // local: 14.5 / 72.6
  'export the whole view to CSV (bulk)': {10000: 80, 50000: 360},
  // local: 0.3 / 0.12
  'scroll window lookup x1000': {10000: 6, 50000: 6},
  // local: 0.17 / 0.84
  'variable row metrics build': {10000: 6, 50000: 14},
};
