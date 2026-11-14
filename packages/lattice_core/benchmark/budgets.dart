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
library;

/// Ceiling per operation, keyed by the row count it was measured at.
const Map<String, Map<int, double>> benchmarkCeilings = {
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
};
