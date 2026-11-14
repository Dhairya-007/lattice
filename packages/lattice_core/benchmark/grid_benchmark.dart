// Measures the operations a user performs on a large grid.
//
//   dart run benchmark/grid_benchmark.dart
//   dart run benchmark/grid_benchmark.dart 10000 50000 200000
//   dart run benchmark/grid_benchmark.dart --check      # fail on a breach
//   dart run benchmark/grid_benchmark.dart --markdown   # a table to publish
//
// Every figure is the median of several runs, because a single run on a cold
// JIT measures the compiler rather than the code. Numbers are only comparable
// against another run on the same machine.
import 'dart:io' show exitCode;
import 'dart:math';

import 'package:lattice_core/lattice_core.dart';

import 'budgets.dart';

/// A log line, the shape of data people actually put in a grid this size.
class LogEntry {
  LogEntry({
    required this.id,
    required this.service,
    required this.level,
    required this.message,
    required this.latencyMs,
    required this.at,
    required this.acknowledged,
  });

  final int id;
  final String service;
  final String level;
  final String message;
  final num latencyMs;
  final DateTime at;
  final bool acknowledged;
}

const _services = [
  'checkout',
  'auth',
  'search',
  'billing',
  'notifications',
  'inventory',
  'shipping',
];
const _levels = ['debug', 'info', 'warn', 'error'];
const _messages = [
  'request completed',
  'cache miss, falling back to origin',
  'retrying upstream call',
  'token refreshed',
  'rate limit reached',
  'connection reset by peer',
  'queue depth above threshold',
];

List<LogEntry> generate(int count) {
  final random = Random(7);
  final start = DateTime(2026, 1, 1);
  return [
    for (var i = 0; i < count; i++)
      LogEntry(
        id: i + 1,
        service: _services[random.nextInt(_services.length)],
        level: _levels[random.nextInt(_levels.length)],
        message: _messages[random.nextInt(_messages.length)],
        latencyMs: 4 + random.nextInt(1800),
        at: start.add(Duration(seconds: i * 7 + random.nextInt(7))),
        acknowledged: random.nextInt(4) == 0,
      ),
  ];
}

List<GridColumn<LogEntry>> columns() => [
      GridColumn<LogEntry>(
        field: 'id',
        type: ColumnType.number,
        value: (r) => r.id,
      ),
      GridColumn<LogEntry>(
        field: 'at',
        type: ColumnType.date,
        value: (r) => r.at,
        format: (v) => (v! as DateTime).toIso8601String(),
      ),
      GridColumn<LogEntry>(field: 'service', value: (r) => r.service),
      GridColumn<LogEntry>(field: 'level', value: (r) => r.level),
      GridColumn<LogEntry>(field: 'message', value: (r) => r.message),
      GridColumn<LogEntry>(
        field: 'latencyMs',
        type: ColumnType.number,
        value: (r) => r.latencyMs,
        format: (v) => '${v ?? 0} ms',
      ),
      GridColumn<LogEntry>(
        field: 'acknowledged',
        type: ColumnType.boolean,
        value: (r) => r.acknowledged,
      ),
    ];

/// Median wall-clock milliseconds for [body], after [warmup] untimed runs.
double measure(void Function() body, {int runs = 7, int warmup = 2}) {
  for (var i = 0; i < warmup; i++) {
    body();
  }
  final samples = <double>[];
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    body();
    watch.stop();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

/// Exit code when `--check` finds an operation over its ceiling.
const int _breachExitCode = 1;

void main(List<String> args) {
  final check = args.contains('--check');
  final markdown = args.contains('--markdown');
  final sizeArgs = [
    for (final a in args)
      if (!a.startsWith('--')) a
  ];
  final sizes = sizeArgs.isEmpty
      ? const [10000, 50000]
      : sizeArgs.map(int.parse).toList();

  if (markdown) {
    print('### Lattice engine benchmark');
    print('');
    print('Median of 7 runs, milliseconds, lower is better. '
        'Ceilings are in `benchmark/budgets.dart`.');
    print('');
    print('| operation | ${sizes.map(_k).join(' | ')} |');
    print('| --- | ${sizes.map((_) => '---:').join(' | ')} |');
  } else {
    print('Lattice engine benchmark');
    print('median of 7 runs, milliseconds, lower is better\n');
    print([
      'operation'.padRight(40),
      ...sizes.map((s) => _k(s).padLeft(10)),
    ].join());
    print('-' * (40 + 10 * sizes.length));
  }

  final results = <String, List<double>>{};

  void record(String label, double Function(int size) run) {
    final row = [for (final size in sizes) run(size)];
    results[label] = row;
    if (markdown) {
      final ceilings = benchmarkCeilings[label.trim()];
      final cells = [
        for (var i = 0; i < sizes.length; i++)
          () {
            final ms = row[i].toStringAsFixed(2);
            final ceiling = ceilings?[sizes[i]];
            if (ceiling == null) return ms;
            return row[i] > ceiling ? '**$ms** (over $ceiling)' : ms;
          }(),
      ];
      print('| ${label.trim()} | ${cells.join(' | ')} |');
    } else {
      print([
        label.padRight(40),
        ...row.map((ms) => ms.toStringAsFixed(2).padLeft(10)),
      ].join());
    }
  }

  // Built once per size: the benchmark measures operations on an existing
  // grid, not the one-off cost of creating it.
  final grids = <int, GridController<LogEntry>>{};
  final sources = <int, InMemoryDataSource<LogEntry>>{};
  for (final size in sizes) {
    final source = InMemoryDataSource<LogEntry>(generate(size));
    sources[size] = source;
    grids[size] = GridController<LogEntry>(
      columns: columns(),
      dataSource: source,
    );
  }

  record('first load (no sort, no filter)', (size) {
    final grid = grids[size]!;
    return measure(() {
      grid.clearSorts();
      grid.clearFilters();
    });
  });

  record('sort by one column', (size) {
    final grid = grids[size]!;
    var ascending = true;
    return measure(() {
      grid.setSorts([
        SortSpec(
          'latencyMs',
          direction:
              ascending ? SortDirection.ascending : SortDirection.descending,
        ),
      ]);
      ascending = !ascending;
    });
  });

  record('sort by three columns', (size) {
    final grid = grids[size]!;
    var ascending = true;
    return measure(() {
      grid.setSorts([
        const SortSpec('service'),
        const SortSpec('level'),
        SortSpec(
          'latencyMs',
          direction:
              ascending ? SortDirection.ascending : SortDirection.descending,
        ),
      ]);
      ascending = !ascending;
    });
  });

  record('filter one column', (size) {
    final grid = grids[size]!;
    grid.clearSorts();
    var i = 0;
    return measure(() {
      grid.setColumnFilter(
        'level',
        FilterCondition(
          field: 'level',
          operator: FilterOperator.equals,
          value: _levels[i++ % _levels.length],
        ),
      );
    });
  });

  record('search across every column', (size) {
    final grid = grids[size]!;
    grid.clearFilters();
    const terms = ['retry', 'reset', 'token', 'queue'];
    var i = 0;
    return measure(() => grid.setSearch(terms[i++ % terms.length]));
  });

  record('search, per keystroke while typing', (size) {
    final grid = grids[size]!;
    const word = 'retrying';
    // What the user actually does: one query per character, not one query.
    // Reported per keystroke, so it can be read against the frame budget.
    final total = measure(() {
      for (var i = 1; i <= word.length; i++) {
        grid.setSearch(word.substring(0, i));
      }
      grid.setSearch('');
    });
    return total / word.length;
  });

  record('page change, 100 rows a page', (size) {
    final grid = grids[size]!;
    grid.clearFilters();
    grid.setSorts(const [SortSpec('at')]);
    grid.setPageSize(100);
    return measure(() {
          for (var page = 0; page < 10; page++) {
            grid.goToPage(page);
          }
        }) /
        10;
  });

  record('group by one column, with 3 aggregates', (size) {
    final grid = grids[size]!;
    grid.setPageSize(null);
    grid.clearGroups();
    var on = true;
    return measure(() {
      if (on) {
        grid.groupBy('service');
      } else {
        grid.clearGroups();
      }
      on = !on;
    });
  });

  record('toggle a group open and shut', (size) {
    final grid = grids[size]!;
    grid.setGroups(const [GroupSpec('service')]);
    final path = (grid.visibleRows.first as GroupGridRow<LogEntry>).path;
    return measure(() {
      grid.toggleGroup(path);
      grid.toggleGroup(path);
    });
  });

  record('export the whole view to CSV (bulk)', (size) {
    final grid = grids[size]!;
    grid.clearGroups();
    grid.setPageSize(null);
    return measure(grid.exportCsv, runs: 3, warmup: 1);
  });

  record('scroll window lookup x1000', (size) {
    final metrics = RowMetrics.uniform(rowCount: size, rowHeight: 40);
    return measure(() {
      for (var i = 0; i < 1000; i++) {
        metrics.windowFor(
          scrollOffset: (i * 37) % (size * 40),
          viewportExtent: 800,
        );
      }
    });
  });

  record('variable row metrics build', (size) {
    return measure(
      () => RowMetrics.variable(
        rowCount: size,
        heightOf: (i) => i.isEven ? 40 : 64,
      ),
      runs: 3,
      warmup: 1,
    );
  });

  print('');
  print('Interactive budget is one frame, 16.7 ms. Anything above that is');
  print('a visible stall when the user types, sorts or pages.');

  final slow = <String>[];
  for (final entry in results.entries) {
    // A bulk export is a deliberate, one-off action; measuring it against a
    // frame would be meaningless.
    if (entry.key.contains('(bulk)')) continue;
    if (entry.value.any((ms) => ms > 16.7)) slow.add(entry.key.trim());
  }
  if (slow.isEmpty) {
    print('');
    print('Every operation fits in a frame at every size measured.');
  } else {
    print('');
    print('Over budget somewhere: ${slow.join(', ')}');
  }

  // Keep the sources alive to the end so nothing is collected mid-run.
  print('');
  print('(rows held: ${sources.values.map((s) => s.length).join(', ')})');

  final breaches = _breaches(results, sizes);
  if (breaches.isNotEmpty) {
    print('');
    print('Over the checked-in ceiling:');
    for (final breach in breaches) {
      print('  $breach');
    }
    print('');
    print('Either this is a regression, or the operation now earns its cost '
        'and benchmark/budgets.dart should say so.');
  }
  if (check && breaches.isNotEmpty) exitCode = _breachExitCode;
}

/// Operations that cost more than [benchmarkCeilings] allows.
///
/// A size with no ceiling recorded is not checked rather than treated as
/// zero: the benchmark takes any row counts on the command line, and a run
/// at 200k is a measurement, not a failure.
List<String> _breaches(Map<String, List<double>> results, List<int> sizes) {
  final out = <String>[];
  for (final entry in results.entries) {
    final label = entry.key.trim();
    final ceilings = benchmarkCeilings[label];
    if (ceilings == null) continue;
    for (var i = 0; i < sizes.length; i++) {
      final ceiling = ceilings[sizes[i]];
      if (ceiling == null) continue;
      final ms = entry.value[i];
      if (ms > ceiling) {
        out.add('$label at ${_k(sizes[i])}: '
            '${ms.toStringAsFixed(2)} ms, ceiling $ceiling ms');
      }
    }
  }
  return out;
}

String _k(int n) => n >= 1000 ? '${n ~/ 1000}k' : '$n';
