// Renders the labelled anatomy diagrams used in the README.
//
//   dart run tool/render_anatomy.dart
//
// This draws a diagram of the grid's parts, not a screenshot: the point is to
// name the pieces and show how they relate. The real app is in
// packages/lattice_flutter/example - see docs/demo.md for capturing a GIF.
//
// It is committed so the diagrams can be regenerated when the anatomy changes,
// rather than being hand-edited XML that drifts.
import 'dart:io';

/// Colours, kept parallel between the two themes so the diagram reads the same
/// way in both. They mirror what LatticeGridTheme derives from a Material
/// theme seeded with #3B5BDB.
class Palette {
  const Palette({
    required this.name,
    required this.page,
    required this.surface,
    required this.header,
    required this.groupRow,
    required this.stripe,
    required this.footer,
    required this.line,
    required this.strongLine,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.selection,
    required this.error,
    required this.callout,
  });

  final String name;
  final String page;
  final String surface;
  final String header;
  final String groupRow;
  final String stripe;
  final String footer;
  final String line;
  final String strongLine;
  final String text;
  final String muted;
  final String accent;
  final String accentSoft;
  final String selection;
  final String error;
  final String callout;
}

const light = Palette(
  name: 'light',
  page: '#ffffff',
  surface: '#ffffff',
  header: '#f1f3f7',
  groupRow: '#e9ecf4',
  stripe: '#fafbfd',
  footer: '#f4f6fa',
  line: '#dfe3ec',
  strongLine: '#b9c0d0',
  text: '#1b1e28',
  muted: '#6b7280',
  accent: '#3b5bdb',
  accentSoft: '#dbe2fb',
  selection: '#c8d4fb',
  error: '#d64545',
  callout: '#8b93a7',
);

const dark = Palette(
  name: 'dark',
  page: '#14161c',
  surface: '#191c24',
  header: '#23273233',
  groupRow: '#272c38',
  stripe: '#1d212a',
  footer: '#20242e',
  line: '#333948',
  strongLine: '#4b5366',
  text: '#e6e8ee',
  muted: '#9aa2b4',
  accent: '#8da2fb',
  accentSoft: '#2b3356',
  selection: '#33406e',
  error: '#f08a8a',
  callout: '#79819a',
);

// -- Geometry ---------------------------------------------------------------

const width = 1180.0;
const height = 470.0;
const gridLeft = 28.0;
const gridTop = 86.0;
const gridWidth = 596.0;
const headerHeight = 30.0;
const filterHeight = 26.0;
const rowHeight = 26.0;
const footerHeight = 30.0;

/// Column widths, summing to [gridWidth]. The first is the frozen one.
const columns = <(String, double, bool)>[
  ('Service', 200, true),
  ('Level', 86, false),
  ('Message', 172, false),
  ('Latency', 74, false),
  ('Ack', 64, false),
];

const rows = <(String, String, String, String, String)>[
  ('checkout', 'error', 'connection reset by peer', '1 204 ms', '—'),
  ('checkout', 'warn', 'rate limit reached', '860 ms', '✓'),
  ('checkout', 'info', 'request completed', '42 ms', '✓'),
];

/// A label outside the grid, with where it points and where it wants to sit.
class Callout {
  Callout(this.label, {required this.fromX, required this.fromY, double? at})
    : preferredY = at ?? fromY;

  final String label;
  final double fromX;
  final double fromY;
  final double preferredY;
}

String svg(Palette p) {
  final out = StringBuffer();
  final labels = <Callout>[];

  out.writeln(
    '<svg xmlns="http://www.w3.org/2000/svg" '
    'viewBox="0 0 ${width.toInt()} ${height.toInt()}" '
    'width="${width.toInt()}" height="${height.toInt()}" '
    'font-family="ui-sans-serif, -apple-system, Segoe UI, Roboto, sans-serif" '
    'role="img" aria-label="Anatomy of the Lattice data grid">',
  );
  out.writeln('<rect width="100%" height="100%" fill="${p.page}"/>');

  // Title.
  out.writeln(
    _text(
      'Lattice',
      x: gridLeft,
      y: 34,
      size: 19,
      weight: 700,
      fill: p.text,
    ),
  );
  out.writeln(
    _text(
      'anatomy of the grid — every part below is a feature, not a mock-up of one',
      x: gridLeft,
      y: 52,
      size: 11.5,
      fill: p.muted,
    ),
  );

  // Search box, standing in for the app's own toolbar.
  out.writeln(
    _rect(gridLeft, 62, 180, 18, fill: p.surface, stroke: p.line, radius: 4),
  );
  out.writeln(
    _text('search 50,000 rows', x: gridLeft + 8, y: 74.5, size: 10, fill: p.muted),
  );

  var y = gridTop;
  final frozenWidth = columns.first.$2;

  // Header row.
  out.writeln(_rect(gridLeft, y, gridWidth, headerHeight, fill: p.header));
  var x = gridLeft;
  for (var i = 0; i < columns.length; i++) {
    final (title, w, _) = columns[i];
    final isLatency = title == 'Latency';
    out.writeln(
      _text(
        title,
        x: isLatency ? x + w - 8 : x + 8,
        y: y + 19.5,
        size: 11,
        weight: 600,
        fill: p.text,
        anchor: isLatency ? 'end' : 'start',
      ),
    );
    if (title == 'Level') {
      // Sort indicator with its level number, as a multi-column sort shows.
      out.writeln(_arrow(x + 44, y + 15, p.accent));
      out.writeln(
        _text('1', x: x + 54, y: y + 19, size: 8.5, weight: 700, fill: p.accent),
      );
    }
    if (i > 0) out.writeln(_vline(x, y, headerHeight, p.line));
    x += w;
  }
  labels.add(
    Callout(
      'Header: tap to sort, ctrl-click for multi-column, drag the edge to resize',
      fromX: gridLeft + gridWidth - 12,
      fromY: y + 15,
      at: y + 8,
    ),
  );
  y += headerHeight;

  // Filter row.
  out.writeln(_rect(gridLeft, y, gridWidth, filterHeight, fill: p.header));
  x = gridLeft;
  for (var i = 0; i < columns.length; i++) {
    final w = columns[i].$2;
    out.writeln(
      _rect(
        x + 5,
        y + 4,
        w - 10,
        filterHeight - 8,
        fill: p.surface,
        stroke: p.line,
        radius: 3,
      ),
    );
    out.writeln(
      _text(
        i == 1 ? 'error' : 'filter',
        x: x + 11,
        y: y + 17,
        size: 9.5,
        fill: i == 1 ? p.text : p.callout,
      ),
    );
    x += w;
  }
  labels.add(
    Callout(
      'Filter row: operator chosen from the column type',
      fromX: gridLeft + gridWidth - 12,
      fromY: y + 13,
      at: y + 30,
    ),
  );
  y += filterHeight;

  // Group header row, with a subtotal under its own column.
  out.writeln(_rect(gridLeft, y, gridWidth, rowHeight, fill: p.groupRow));
  out.writeln(_chevron(gridLeft + 12, y + rowHeight / 2, p.text));
  out.writeln(
    _text(
      'service: checkout',
      x: gridLeft + 24,
      y: y + 17,
      size: 11,
      weight: 600,
      fill: p.text,
    ),
  );
  out.writeln(
    _text('(1 284)', x: gridLeft + 152, y: y + 17, size: 10, fill: p.muted),
  );
  out.writeln(
    _text(
      'avg 702 ms',
      x: gridLeft + _offsetOf('Latency') + _widthOf('Latency') - 8,
      y: y + 17,
      size: 9.5,
      fill: p.muted,
      anchor: 'end',
    ),
  );
  labels.add(
    Callout(
      'Group row: count, and this group’s aggregate under its own column',
      fromX: gridLeft + gridWidth - 12,
      fromY: y + 13,
      at: y + 54,
    ),
  );
  y += rowHeight;

  // Data rows.
  final selectedTop = y + rowHeight;
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final cells = [row.$1, row.$2, row.$3, row.$4, row.$5];
    out.writeln(
      _rect(
        gridLeft,
        y,
        gridWidth,
        rowHeight,
        fill: r.isOdd ? p.stripe : p.surface,
      ),
    );
    x = gridLeft;
    for (var c = 0; c < columns.length; c++) {
      final (title, w, _) = columns[c];
      // A selected range over two rows and two columns.
      final inRange = r >= 1 && r <= 2 && (c == 2 || c == 3);
      if (inRange) {
        out.writeln(_rect(x, y, w, rowHeight, fill: p.selection));
      }
      final isNumeric = title == 'Latency';
      final isEditing = r == 0 && c == 3;
      if (isEditing) {
        out.writeln(
          _rect(
            x + 3,
            y + 3,
            w - 6,
            rowHeight - 6,
            fill: p.surface,
            stroke: p.error,
            radius: 3,
            strokeWidth: 1.6,
          ),
        );
        out.writeln(
          _text(
            '-12',
            x: x + w - 10,
            y: y + 17,
            size: 10.5,
            fill: p.text,
            anchor: 'end',
          ),
        );
      } else {
        out.writeln(
          _text(
            cells[c],
            x: isNumeric ? x + w - 8 : x + 8,
            y: y + 17,
            size: 10.5,
            fill: c == 1 ? p.text : p.text,
            anchor: isNumeric ? 'end' : 'start',
            weight: c == 1 ? 600 : 400,
          ),
        );
      }
      if (c > 0) out.writeln(_vline(x, y, rowHeight, p.line));
      x += w;
    }
    out.writeln(_hline(gridLeft, y + rowHeight, gridWidth, p.line));
    y += rowHeight;
  }

  // Validation message for the cell being edited.
  out.writeln(
    _text(
      'Must be at least 0',
      x: gridLeft + _offsetOf('Ack') + 8,
      y: gridTop + headerHeight + filterHeight + rowHeight + 17,
      size: 9.5,
      fill: p.error,
    ),
  );
  labels.add(
    Callout(
      'Editing in place: validated, with the error shown and Escape to roll back',
      fromX: gridLeft + gridWidth - 12,
      fromY: gridTop + headerHeight + filterHeight + rowHeight + 13,
      at: gridTop + 112,
    ),
  );
  labels.add(
    Callout(
      'Range selection: copies as TSV with ctrl-C',
      fromX: gridLeft + _offsetOf('Ack'),
      fromY: selectedTop + rowHeight,
      at: gridTop + 146,
    ),
  );

  // Rows continue beyond the viewport: virtualization.
  out.writeln(
    _rect(gridLeft, y, gridWidth, rowHeight, fill: p.surface),
  );
  out.writeln(
    _text(
      '⋮  49 993 more rows, only the visible ones are built',
      x: gridLeft + 8,
      y: y + 17,
      size: 10,
      fill: p.callout,
    ),
  );
  out.writeln(_hline(gridLeft, y + rowHeight, gridWidth, p.line));
  labels.add(
    Callout(
      'Virtualized rows: 50k in, one screen built',
      fromX: gridLeft + gridWidth - 12,
      fromY: y + 13,
      at: gridTop + 180,
    ),
  );
  y += rowHeight;

  // Footer.
  out.writeln(_rect(gridLeft, y, gridWidth, footerHeight, fill: p.footer));
  out.writeln(_hline(gridLeft, y, gridWidth, p.line));
  out.writeln(
    _text(
      '1 284 of 50 000 rows · 4 selected',
      x: gridLeft + 8,
      y: y + 19,
      size: 10,
      fill: p.muted,
    ),
  );
  out.writeln(
    _text(
      'avg 702 ms   slowest 1 204 ms',
      x: gridLeft + 210,
      y: y + 19,
      size: 10,
      fill: p.muted,
    ),
  );
  out.writeln(
    _text(
      '‹  page 1 of 13  ›',
      x: gridLeft + gridWidth - 8,
      y: y + 19,
      size: 10,
      fill: p.muted,
      anchor: 'end',
    ),
  );
  labels.add(
    Callout(
      'Footer: counts, grid-wide aggregates, pagination',
      fromX: gridLeft + gridWidth - 12,
      fromY: y + 15,
      at: y + 26,
    ),
  );
  y += footerHeight;

  // Grid outline, drawn last so it sits above the fills.
  out.writeln(
    _rect(
      gridLeft,
      gridTop,
      gridWidth,
      y - gridTop,
      fill: 'none',
      stroke: p.strongLine,
      radius: 6,
    ),
  );

  // The frozen pane divider runs the full height of the grid.
  out.writeln(
    '<line x1="${gridLeft + frozenWidth}" y1="$gridTop" '
    'x2="${gridLeft + frozenWidth}" y2="$y" stroke="${p.strongLine}" '
    'stroke-width="1.5"/>',
  );
  labels.add(
    Callout(
      'Frozen column: its own pane, locked to the body’s scroll',
      fromX: gridLeft + frozenWidth,
      fromY: gridTop + headerHeight + filterHeight + rowHeight * 3,
      at: gridTop + 214,
    ),
  );

  out.write(_placeCallouts(labels, p));

  out.writeln('</svg>');
  return out.toString();
}

double _offsetOf(String title) {
  var x = 0.0;
  for (final (name, w, _) in columns) {
    if (name == title) return x;
    x += w;
  }
  return x;
}

double _widthOf(String title) =>
    columns.firstWhere((c) => c.$1 == title, orElse: () => ('', 0, false)).$2;

String _rect(
  double x,
  double y,
  double w,
  double h, {
  required String fill,
  String? stroke,
  double radius = 0,
  double strokeWidth = 1,
}) {
  final strokeAttr = stroke == null
      ? ''
      : ' stroke="$stroke" stroke-width="$strokeWidth"';
  final radiusAttr = radius == 0 ? '' : ' rx="$radius"';
  return '<rect x="$x" y="$y" width="$w" height="$h" fill="$fill"'
      '$strokeAttr$radiusAttr/>';
}

String _text(
  String value, {
  required double x,
  required double y,
  required double size,
  required String fill,
  int weight = 400,
  String anchor = 'start',
}) {
  return '<text x="$x" y="$y" font-size="$size" font-weight="$weight" '
      'fill="$fill" text-anchor="$anchor">${_escape(value)}</text>';
}

String _vline(double x, double y, double h, String color) =>
    '<line x1="$x" y1="$y" x2="$x" y2="${y + h}" stroke="$color" '
    'stroke-width="1"/>';

String _hline(double x, double y, double w, String color) =>
    '<line x1="$x" y1="$y" x2="${x + w}" y2="$y" stroke="$color" '
    'stroke-width="1"/>';

String _arrow(double x, double y, String color) =>
    '<path d="M $x ${y + 4} L $x ${y - 4} M ${x - 3} ${y - 1} L $x ${y - 4} '
    'L ${x + 3} ${y - 1}" stroke="$color" stroke-width="1.4" fill="none" '
    'stroke-linecap="round"/>';

String _chevron(double x, double y, String color) =>
    '<path d="M ${x - 3} ${y - 3} L ${x + 2} $y L ${x - 3} ${y + 3}" '
    'stroke="$color" stroke-width="1.5" fill="none" stroke-linecap="round" '
    'transform="rotate(90 $x $y)"/>';

/// Lays out every label in a column to the right of the grid.
///
/// Callouts are placed in the order they want to appear and pushed down only
/// as far as needed to clear the one above, which keeps each label near the
/// part it names without any two overlapping.
String _placeCallouts(List<Callout> callouts, Palette p) {
  const labelX = gridLeft + gridWidth + 30;
  const lineHeight = 12.0;
  const gap = 9.0;
  const wrapAt = 24;

  final ordered = [...callouts]
    ..sort((a, b) => a.preferredY.compareTo(b.preferredY));

  final out = StringBuffer();
  var cursor = 0.0;
  for (final callout in ordered) {
    final lines = _wrap(callout.label, wrapAt);
    final blockHeight = lines.length * lineHeight;
    var top = callout.preferredY - blockHeight / 2;
    if (top < cursor) top = cursor;
    if (top + blockHeight > height - 8) top = height - 8 - blockHeight;
    cursor = top + blockHeight + gap;

    final anchorY = top + blockHeight / 2;
    // Leaders turn in the gutter just outside the grid, never inside it: a
    // vertical line crossing the table reads as part of the table.
    const midX = gridLeft + gridWidth + 12;
    out.writeln(
      '<path d="M ${callout.fromX} ${callout.fromY} '
      'L $midX ${callout.fromY} L $midX $anchorY L ${labelX - 8} $anchorY" '
      'stroke="${p.callout}" stroke-width="0.9" fill="none" '
      'stroke-dasharray="2 2"/>',
    );
    out.writeln(
      '<circle cx="${callout.fromX}" cy="${callout.fromY}" r="2" '
      'fill="${p.callout}"/>',
    );
    for (var i = 0; i < lines.length; i++) {
      out.writeln(
        _text(
          lines[i],
          x: labelX,
          y: top + lineHeight * (i + 1) - 3,
          size: 10,
          fill: p.muted,
        ),
      );
    }
  }
  return out.toString();
}

/// Greedy wrap at [limit] characters, so a label stays inside the canvas.
List<String> _wrap(String label, int limit) {
  final lines = <String>[];
  var current = '';
  for (final word in label.split(' ')) {
    final candidate = current.isEmpty ? word : '$current $word';
    if (candidate.length > limit && current.isNotEmpty) {
      lines.add(current);
      current = word;
    } else {
      current = candidate;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

void main() {
  for (final palette in [light, dark]) {
    final file = File('docs/anatomy-${palette.name}.svg');
    file.writeAsStringSync(svg(palette));
    stdout.writeln('wrote ${file.path}');
  }
}
