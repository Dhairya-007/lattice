import 'dart:async';
import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:lattice_flutter/lattice_flutter.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const LatticeExampleApp());

const _accent = Color(0xFF6C7BFF);

class LatticeExampleApp extends StatelessWidget {
  const LatticeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lattice',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const ConsolePage(),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF0B0D13)
          : const Color(0xFFF6F7FB),
      visualDensity: VisualDensity.compact,
    );
  }
}

// -- Data ------------------------------------------------------------------

class LogEntry {
  LogEntry({
    required this.id,
    required this.service,
    required this.level,
    required this.message,
    required this.latencyMs,
    required this.at,
    required this.region,
    this.acknowledged = false,
  });

  final int id;
  final String service;
  final String level;
  String message;
  num latencyMs;
  final DateTime at;
  final String region;
  bool acknowledged;
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
const _regions = ['eu-west', 'us-east', 'ap-south'];
const _messages = [
  'request completed',
  'cache miss, falling back to origin',
  'retrying upstream call',
  'token refreshed',
  'rate limit reached',
  'connection reset by peer',
  'queue depth above threshold',
  'circuit breaker opened',
];

List<LogEntry> generateLogs(int count) {
  final random = Random(7);
  final start = DateTime(2026, 11, 1);
  return [
    for (var i = 0; i < count; i++)
      LogEntry(
        id: i + 1,
        service: _services[random.nextInt(_services.length)],
        level: _levels[random.nextInt(_levels.length)],
        message: _messages[random.nextInt(_messages.length)],
        latencyMs: 4 + random.nextInt(1800),
        at: start.add(Duration(seconds: i * 11 + random.nextInt(11))),
        region: _regions[random.nextInt(_regions.length)],
        acknowledged: random.nextInt(4) == 0,
      ),
  ];
}

// -- Page ------------------------------------------------------------------

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  late final InMemoryDataSource<LogEntry> _source;
  late final GridController<LogEntry> _controller;
  final TextEditingController _search = TextEditingController();

  GridDensity _density = GridDensity.standard;
  bool _grouped = false;
  bool _filterRow = true;
  bool _live = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _source = InMemoryDataSource<LogEntry>(generateLogs(50000));
    _controller = GridController<LogEntry>(
      columns: _columns(),
      dataSource: _source,
      sorts: const [SortSpec('at', direction: SortDirection.descending)],
      aggregations: const [
        Aggregation.count('id', label: 'lines'),
        Aggregation.average('latencyMs', label: 'avg'),
        Aggregation.max('latencyMs', label: 'peak'),
      ],
      selectionMode: SelectionMode.cellRange,
      stackedHeaders: const [
        HeaderRow([
          HeaderBand(title: 'Event', fields: ['at', 'service', 'region']),
          HeaderBand(title: 'Detail', fields: ['level', 'message']),
          HeaderBand(title: 'Health', fields: ['latencyMs', 'acknowledged']),
        ]),
      ],
      columnFit: ColumnFit.stretch,
    );
    _controller.addListener(_onGridChanged);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.removeListener(_onGridChanged);
    _search.dispose();
    _controller.dispose();
    _source.dispose();
    super.dispose();
  }

  void _onGridChanged() {
    // The stat strip reads aggregates off the controller, so it has to
    // rebuild when the query does.
    if (mounted) setState(() {});
  }

  /// Rewrites a handful of rows a second, to show the change flash.
  void _toggleLive(bool on) {
    setState(() => _live = on);
    _ticker?.cancel();
    if (!on) return;
    final random = Random();
    _ticker = Timer.periodic(const Duration(milliseconds: 900), (_) {
      final rows = _source.rows;
      if (rows.isEmpty) return;
      _source.batch(() {
        for (var i = 0; i < 6; i++) {
          final index = random.nextInt(min(rows.length, 400));
          rows[index].latencyMs = 4 + random.nextInt(1800);
          _source.replaceAt(index, rows[index]);
        }
      });
    });
  }

  List<GridColumn<LogEntry>> _columns() => [
    GridColumn<LogEntry>(
      field: 'at',
      title: 'Time',
      type: ColumnType.date,
      value: (r) => r.at,
      width: 120,
      pin: ColumnPin.start,
      groupable: false,
      format: (v) {
        final at = v! as DateTime;
        String two(int n) => n.toString().padLeft(2, '0');
        return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
      },
    ),
    GridColumn<LogEntry>(field: 'service', value: (r) => r.service, width: 130),
    GridColumn<LogEntry>(field: 'region', value: (r) => r.region, width: 110),
    GridColumn<LogEntry>(
      field: 'level',
      value: (r) => r.level,
      width: 110,
      // Severity, not alphabet: error has to sort above warn.
      comparator: (a, b) => _levels
          .indexOf(a! as String)
          .compareTo(_levels.indexOf(b! as String)),
      rule: const ValueToneRule({
        'error': CellTone.severe,
        'warn': CellTone.caution,
        'info': CellTone.info,
        'debug': CellTone.neutral,
      }),
    ),
    GridColumn<LogEntry>(
      field: 'message',
      value: (r) => r.message,
      width: 300,
      setValue: (r, v) {
        r.message = (v ?? '') as String;
        return null;
      },
      validator: requiredValue('A log line needs a message'),
      groupable: false,
    ),
    GridColumn<LogEntry>(
      field: 'latencyMs',
      title: 'Latency',
      type: ColumnType.number,
      value: (r) => r.latencyMs,
      width: 130,
      format: (v) => '${v ?? 0} ms',
      setValue: (r, v) {
        r.latencyMs = (v ?? 0) as num;
        return null;
      },
      validator: numberRange(min: 0, max: 60000),
      // A bar for scale, and a tone once it crosses a second.
      rule: const MergedRule([
        DataBarRule(fromZero: true),
        ThresholdRule(threshold: 1000, tone: CellTone.severe, bold: true),
      ]),
    ),
    GridColumn<LogEntry>(
      field: 'acknowledged',
      title: 'Ack',
      type: ColumnType.boolean,
      value: (r) => r.acknowledged,
      width: 80,
      pin: ColumnPin.end,
      groupable: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return Scaffold(
      body: Column(
        children: [
          _Masthead(
            controller: _controller,
            search: _search,
            density: _density,
            grouped: _grouped,
            filterRow: _filterRow,
            live: _live,
            onDensity: (d) => setState(() => _density = d),
            onGrouped: (on) {
              setState(() => _grouped = on);
              if (on) {
                _controller.groupBy('service');
              } else {
                _controller.clearGroups();
              }
            },
            onFilterRow: (on) => setState(() => _filterRow = on),
            onLive: _toggleLive,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.5 : 0.07,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: LatticeDataGrid<LogEntry>(
                  controller: _controller,
                  showFilterRow: _filterRow,
                  showCheckboxColumn: true,
                  highlightChanges: true,
                  rowId: (row) => row.id,
                  autofocus: true,
                  theme: LatticeGridTheme.of(context, density: _density)
                      .copyWith(
                        stripeRows: true,
                        cornerRadius: 16,
                        focusedCellBorder: _accent,
                      ),
                  cellBuilder: (context, column, row) => switch (column.field) {
                    'level' => _LevelPill(level: row.level),
                    'acknowledged' => Icon(
                      row.acknowledged
                          ? Icons.check_circle_rounded
                          : Icons.remove_rounded,
                      size: 16,
                      color: row.acknowledged
                          ? const Color(0xFF3DD68C)
                          : scheme.outline,
                    ),
                    _ => Text(
                      column.formattedValue(row),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: column.effectiveAlign == ColumnAlign.end
                          ? TextAlign.end
                          : TextAlign.start,
                    ),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Masthead --------------------------------------------------------------

class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.controller,
    required this.search,
    required this.density,
    required this.grouped,
    required this.filterRow,
    required this.live,
    required this.onDensity,
    required this.onGrouped,
    required this.onFilterRow,
    required this.onLive,
  });

  final GridController<LogEntry> controller;
  final TextEditingController search;
  final GridDensity density;
  final bool grouped;
  final bool filterRow;
  final bool live;
  final ValueChanged<GridDensity> onDensity;
  final ValueChanged<bool> onGrouped;
  final ValueChanged<bool> onFilterRow;
  final ValueChanged<bool> onLive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = controller.aggregates['latencyMs.max'];
    final average = controller.aggregates['latencyMs.average'];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        // A quiet gradient, so the chrome recedes and the data does not.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accent.withValues(alpha: 0.16),
            scheme.surface.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_accent, Color(0xFF9B7BFF)],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.grid_on_rounded,
                  size: 17,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Lattice',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'service log console',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              _Stat(
                label: 'rows',
                value: _compact(controller.matchedCount),
                accent: _accent,
              ),
              _Stat(
                label: 'avg',
                value: average == null ? '—' : '${(average as num).round()} ms',
                accent: const Color(0xFF3DD68C),
              ),
              _Stat(
                label: 'peak',
                value: peak == null ? '—' : '$peak ms',
                accent: const Color(0xFFFF7A7A),
              ),
              _Stat(
                label: 'selected',
                value: '${controller.selection.rowCount}',
                accent: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 280,
                height: 38,
                child: TextField(
                  controller: search,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surface,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    hintText: 'Search 50,000 lines',
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: scheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: scheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _accent, width: 1.6),
                    ),
                  ),
                  onChanged: controller.setSearch,
                ),
              ),
              const SizedBox(width: 12),
              _Segmented<GridDensity>(
                value: density,
                onChanged: onDensity,
                options: const {
                  GridDensity.compact: Icons.density_small_rounded,
                  GridDensity.standard: Icons.density_medium_rounded,
                  GridDensity.comfortable: Icons.density_large_rounded,
                },
              ),
              const SizedBox(width: 12),
              _Toggle(
                label: 'Group',
                icon: Icons.workspaces_outline,
                on: grouped,
                onChanged: onGrouped,
              ),
              _Toggle(
                label: 'Filters',
                icon: Icons.filter_alt_outlined,
                on: filterRow,
                onChanged: onFilterRow,
              ),
              _Toggle(
                label: 'Live',
                icon: Icons.bolt_rounded,
                on: live,
                onChanged: onLive,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => controller.setFilter(
                  const FilterCondition(
                    field: 'level',
                    operator: FilterOperator.equals,
                    value: 'error',
                  ),
                ),
                icon: const Icon(Icons.warning_amber_rounded, size: 16),
                label: const Text('Errors'),
              ),
              TextButton.icon(
                onPressed: () {
                  search.clear();
                  controller.clearFilters();
                },
                icon: const Icon(Icons.clear_all_rounded, size: 16),
                label: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _compact(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.accent});

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          // The number changes constantly in live mode; a cross-fade keeps
          // that from reading as flicker.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              value,
              key: ValueKey(value),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.icon,
    required this.on,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: on ? _accent.withValues(alpha: 0.18) : scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: on ? _accent : scheme.outlineVariant,
              width: on ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: on ? _accent : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: on ? _accent : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.onChanged,
    required this.options,
  });

  final T value;
  final ValueChanged<T> onChanged;
  final Map<T, IconData> options;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in options.entries)
            GestureDetector(
              onTap: () => onChanged(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: entry.key == value
                      ? _accent.withValues(alpha: 0.22)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  entry.value,
                  size: 16,
                  color: entry.key == value ? _accent : scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.level});

  final String level;

  static const _colors = {
    'debug': Color(0xFF8A93A6),
    'info': Color(0xFF5B9BFF),
    'warn': Color(0xFFE8A33D),
    'error': Color(0xFFFF6B6B),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[level] ?? const Color(0xFF8A93A6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        level,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
