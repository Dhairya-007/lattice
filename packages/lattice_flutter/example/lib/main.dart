import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lattice_flutter/lattice_flutter.dart';

void main() => runApp(const LatticeExampleApp());

class LatticeExampleApp extends StatelessWidget {
  const LatticeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lattice',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B5BDB),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B5BDB),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const GridDemoPage(),
    );
  }
}

/// One row of the demo: a service log line.
class LogEntry {
  LogEntry({
    required this.id,
    required this.service,
    required this.level,
    required this.message,
    required this.latencyMs,
    required this.at,
    this.acknowledged = false,
  });

  final int id;
  final String service;
  final String level;
  String message;
  num latencyMs;
  final DateTime at;
  bool acknowledged;
}

const _services = ['checkout', 'auth', 'search', 'billing', 'notifications'];
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
        at: start.add(Duration(minutes: i * 3 + random.nextInt(3))),
        acknowledged: random.nextInt(4) == 0,
      ),
  ];
}

class GridDemoPage extends StatefulWidget {
  const GridDemoPage({super.key});

  @override
  State<GridDemoPage> createState() => _GridDemoPageState();
}

class _GridDemoPageState extends State<GridDemoPage> {
  late final InMemoryDataSource<LogEntry> _source;
  late final GridController<LogEntry> _controller;
  final TextEditingController _search = TextEditingController();

  bool _grouped = false;
  bool _filterRow = true;
  bool _paged = false;

  @override
  void initState() {
    super.initState();
    _source = InMemoryDataSource<LogEntry>(generateLogs(20000));
    _controller = GridController<LogEntry>(
      columns: _columns(),
      dataSource: _source,
      sorts: const [SortSpec('at', direction: SortDirection.descending)],
      aggregations: const [
        Aggregation.count('id', label: 'lines'),
        Aggregation.average('latencyMs', label: 'avg ms'),
        Aggregation.max('latencyMs', label: 'slowest'),
      ],
      selectionMode: SelectionMode.cellRange,
      columnFit: ColumnFit.stretch,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _controller.dispose();
    _source.dispose();
    super.dispose();
  }

  List<GridColumn<LogEntry>> _columns() => [
    GridColumn<LogEntry>(
      field: 'id',
      title: '#',
      type: ColumnType.number,
      value: (r) => r.id,
      width: 72,
      pin: ColumnPin.start,
      groupable: false,
    ),
    GridColumn<LogEntry>(
      field: 'at',
      title: 'Time',
      type: ColumnType.date,
      value: (r) => r.at,
      width: 150,
      format: (v) {
        final at = v! as DateTime;
        final h = at.hour.toString().padLeft(2, '0');
        final m = at.minute.toString().padLeft(2, '0');
        return '${at.day}/${at.month} $h:$m';
      },
    ),
    GridColumn<LogEntry>(field: 'service', value: (r) => r.service, width: 140),
    GridColumn<LogEntry>(
      field: 'level',
      value: (r) => r.level,
      width: 110,
      // Severity, not alphabet: error has to sort above warn.
      comparator: (a, b) => _levels
          .indexOf(a! as String)
          .compareTo(_levels.indexOf(b! as String)),
    ),
    GridColumn<LogEntry>(
      field: 'message',
      value: (r) => r.message,
      width: 320,
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
      width: 120,
      format: (v) => '${v ?? 0} ms',
      setValue: (r, v) {
        r.latencyMs = (v ?? 0) as num;
        return null;
      },
      validator: numberRange(min: 0, max: 60000),
    ),
    GridColumn<LogEntry>(
      field: 'acknowledged',
      title: 'Ack',
      type: ColumnType.boolean,
      value: (r) => r.acknowledged,
      width: 90,
      pin: ColumnPin.end,
      groupable: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lattice'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Search 20,000 lines',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _controller.setSearch,
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Group by service'),
                  selected: _grouped,
                  onSelected: (on) {
                    setState(() => _grouped = on);
                    if (on) {
                      _controller.groupBy('service');
                    } else {
                      _controller.clearGroups();
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Filter row'),
                  selected: _filterRow,
                  onSelected: (on) => setState(() => _filterRow = on),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Paginate'),
                  selected: _paged,
                  onSelected: (on) {
                    setState(() => _paged = on);
                    _controller.setPageSize(on ? 100 : null);
                  },
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.warning_amber, size: 16),
                  label: const Text('Errors only'),
                  onPressed: () => _controller.setFilter(
                    const FilterCondition(
                      field: 'level',
                      operator: FilterOperator.equals,
                      value: 'error',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Reset'),
                  onPressed: () {
                    _search.clear();
                    _controller.clearFilters();
                    _controller.clearSorts();
                  },
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy selection',
                  icon: const Icon(Icons.copy_all),
                  onPressed: () {
                    final text = _controller.copySelectionAsText(
                      includeHeader: true,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          text.isEmpty
                              ? 'Nothing selected'
                              : '${text.split('\n').length} lines copied',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LatticeDataGrid<LogEntry>(
              controller: _controller,
              showFilterRow: _filterRow,
              autofocus: true,
              theme: LatticeGridTheme.of(context).copyWith(stripeRows: true),
              cellBuilder: (context, column, row) {
                if (column.field == 'level')
                  return _LevelChip(level: row.level);
                if (column.field == 'acknowledged') {
                  return Icon(
                    row.acknowledged ? Icons.check_circle : Icons.remove,
                    size: 16,
                    color: row.acknowledged
                        ? Colors.green.shade600
                        : Theme.of(context).disabledColor,
                  );
                }
                return Text(
                  column.formattedValue(row),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: column.effectiveAlign == ColumnAlign.end
                      ? TextAlign.end
                      : TextAlign.start,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level});

  final String level;

  static const _colors = {
    'debug': Color(0xFF868E96),
    'info': Color(0xFF1C7ED6),
    'warn': Color(0xFFF08C00),
    'error': Color(0xFFE03131),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[level] ?? const Color(0xFF868E96);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        level,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
