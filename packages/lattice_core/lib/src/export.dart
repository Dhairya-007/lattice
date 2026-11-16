/// Exporting the current view to text formats.
library;

import 'column.dart';
import 'group.dart';
import 'query.dart';
import 'rows.dart';

/// Shaping options shared by the text exporters.
class ExportOptions {
  const ExportOptions({
    this.includeHeader = true,
    this.fields,
    this.delimiter = ',',
    this.lineEnding = '\r\n',
    this.includeGroupRows = true,
    this.groupIndent = '    ',
    this.formatted = true,
    this.sanitizeFormulas = true,
    this.formulaPrefix = "'",
    this.respectCollapsed = true,
  });

  final bool includeHeader;

  /// Columns to export, in order. Defaults to every visible column.
  final List<String>? fields;

  final String delimiter;

  /// CRLF by default, which is what spreadsheet software expects of a CSV.
  final String lineEnding;

  final bool includeGroupRows;
  final String groupIndent;

  /// Whether to export display text (respecting each column's formatter) or
  /// raw values. Raw is the right choice when the file will be re-imported.
  final bool formatted;

  /// Neutralises values a spreadsheet would execute as a formula.
  ///
  /// A cell beginning `=`, `+`, `-`, `@`, tab or carriage return is run as a
  /// formula when the file is opened in Excel, Sheets or LibreOffice, which
  /// makes an export of user-supplied data a delivery mechanism for
  /// [CSV injection](https://owasp.org/www-community/attacks/CSV_Injection).
  ///
  /// On by default: the unsafe behaviour is only ever noticed after it has
  /// been exploited, so it should not be what you get by forgetting. Turn it
  /// off only for a file that is machine-read and must round-trip exactly.
  final bool sanitizeFormulas;

  /// Prepended to a value that would otherwise be read as a formula.
  ///
  /// A leading apostrophe is the spreadsheet convention for "treat this as
  /// text"; it is consumed on import rather than shown as part of the value.
  final String formulaPrefix;

  /// Whether a collapsed group exports as its header alone.
  ///
  /// On by default, because an export documents itself as matching what is on
  /// screen and a collapsed group is not on screen. The expansion state was
  /// accepted and never read, so every row came out whatever the user had
  /// closed. Turn it off to export the whole result regardless.
  final bool respectCollapsed;
}

/// Writes rows as delimiter-separated text.
///
/// Exports what the user is actually looking at - current order, current
/// filters, current grouping - because an export that silently differs from
/// the screen is a bug report waiting to happen.
class CsvExporter<T> {
  const CsvExporter(this.columns, {this.options = const ExportOptions()});

  final List<GridColumn<T>> columns;
  final ExportOptions options;

  List<GridColumn<T>> get _exported {
    final fields = options.fields;
    if (fields == null) {
      return [
        for (final c in columns)
          if (c.visible) c,
      ];
    }
    final byField = {for (final c in columns) c.field: c};
    return [
      for (final field in fields)
        if (byField[field] != null) byField[field]!,
    ];
  }

  /// Exports a flat list of rows.
  String exportRows(List<T> rows) {
    final out = StringBuffer();
    final exported = _exported;
    final numeric = _numericFlags(exported);
    if (options.includeHeader) {
      _writeLine(out, [for (final c in exported) c.title]);
    }
    final cells = List<String>.filled(exported.length, '');
    for (final row in rows) {
      for (var i = 0; i < exported.length; i++) {
        cells[i] = _cell(exported[i], row);
      }
      _writeLine(out, cells, numeric: numeric);
    }
    return out.toString();
  }

  /// Which exported columns hold numbers.
  ///
  /// A number is never a formula, and prefixing it makes a spreadsheet read
  /// the column as text - which is how every negative value in an exported
  /// numeric column became `'-5` and broke the sums the user exported it to
  /// compute.
  List<bool> _numericFlags(List<GridColumn<T>> exported) =>
      [for (final c in exported) c.type == ColumnType.number];

  /// Exports a grouped result, writing one indented header line per group.
  ///
  /// Only the first cell of a row is indented. Indenting every cell turned
  /// each number into text with leading spaces - `"    1450"` - so a
  /// spreadsheet read the whole column as text and its sums came out empty.
  String exportGroups(
      List<GroupNode<T>> groups, GroupExpansionState expansion) {
    final out = StringBuffer();
    final exported = _exported;
    final numeric = _numericFlags(exported);
    if (exported.isEmpty) return '';
    if (options.includeHeader) {
      _writeLine(out, [for (final c in exported) c.title]);
    }

    void walk(List<GroupNode<T>> level) {
      for (final node in level) {
        if (options.includeGroupRows) {
          final label = '${options.groupIndent * node.depth}'
              '${node.label} (${node.rowCount})';
          _writeLine(out, [
            label,
            // An export with a single column has no trailing cells to pad,
            // and List.filled(-1) threw rather than saying so.
            ...List<String>.filled(exported.length - 1, ''),
          ]);
        }
        // A collapsed group is not on screen, and the export says it matches
        // what is on screen.
        if (options.respectCollapsed && !expansion.isExpanded(node.path)) {
          continue;
        }
        if (node.isLeafGroup) {
          final indent = options.groupIndent * (node.depth + 1);
          final cells = List<String>.filled(exported.length, '');
          for (final row in node.rows) {
            for (var i = 0; i < exported.length; i++) {
              final value = _cell(exported[i], row);
              cells[i] = i == 0 ? '$indent$value' : value;
            }
            _writeLine(out, cells, numeric: numeric);
          }
        } else {
          walk(node.children);
        }
      }
    }

    walk(groups);
    return out.toString();
  }

  /// Exports whichever shape [result] carries.
  String exportResult(GridResult<T> result, GroupExpansionState expansion) {
    return result.isGrouped
        ? exportGroups(result.groups, expansion)
        : exportRows(result.rows);
  }

  String _cell(GridColumn<T> column, T row) {
    if (options.formatted) return column.formattedValue(row);
    final raw = column.value(row);
    return raw == null ? '' : '$raw';
  }

  /// Writes one escaped line into [out].
  ///
  /// Writing straight into the buffer avoids building an intermediate list of
  /// escaped cells and then joining it, which at 50k rows was most of the
  /// cost of an export.
  void _writeLine(
    StringBuffer out,
    List<String> cells, {
    List<bool>? numeric,
  }) {
    for (var i = 0; i < cells.length; i++) {
      if (i > 0) out.write(options.delimiter);
      _writeEscaped(
        out,
        cells[i],
        sanitize: numeric == null || i >= numeric.length || !numeric[i],
      );
    }
    out.write(options.lineEnding);
  }

  /// Characters that start a formula in Excel, Sheets and LibreOffice.
  ///
  /// The tab and carriage return are included because a leading one is
  /// stripped by some readers, exposing the character after it - so `\t=cmd`
  /// becomes `=cmd` on import.
  static const _formulaStarters = {0x3d, 0x2b, 0x2d, 0x40, 0x09, 0x0d};

  /// Whether a spreadsheet would execute [value] rather than show it.
  ///
  /// Leading spaces are skipped: spreadsheets trim them on import, so
  /// `"   =cmd"` is executed just as `"=cmd"` is. A grouped export indents
  /// its rows, which would otherwise hide a formula from this check. Tabs
  /// and carriage returns are not skipped - they are starters in their own
  /// right.
  static bool isFormula(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit == 0x20) continue;
      if (!_formulaStarters.contains(unit)) return false;
      // A negative number starts with `-` and is not a formula. Prefixing it
      // made every negative value in an export read as text.
      return num.tryParse(value.trim()) == null;
    }
    return false;
  }

  /// RFC 4180 quoting: wrap in quotes when the value contains the delimiter, a
  /// quote or a newline, and double any embedded quotes.
  void _writeEscaped(
    StringBuffer out,
    String rawValue, {
    bool sanitize = true,
  }) {
    // Sanitise before quoting: the prefix has to end up inside the quotes,
    // or the reader strips it along with them.
    final value = sanitize && options.sanitizeFormulas && isFormula(rawValue)
        ? '${options.formulaPrefix}$rawValue'
        : rawValue;
    var needsQuotes = false;
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      // " \n \r, or the first code unit of the delimiter.
      if (unit == 0x22 || unit == 0x0a || unit == 0x0d) {
        needsQuotes = true;
        break;
      }
      if (unit == _delimiterUnit) {
        needsQuotes = true;
        break;
      }
    }
    if (!needsQuotes) {
      out.write(value);
      return;
    }
    out.write('"');
    out.write(value.replaceAll('"', '""'));
    out.write('"');
  }

  /// First code unit of the delimiter, for the scan above. Multi-character
  /// delimiters are rare and still handled: a false positive only means a
  /// value is quoted when it did not have to be, which readers accept.
  int get _delimiterUnit =>
      options.delimiter.isEmpty ? -1 : options.delimiter.codeUnitAt(0);
}

/// Splits clipboard text back into a grid of cells: the inverse of
/// [toClipboardText].
///
/// Accepts the three line endings a clipboard can carry, because the text may
/// have come from any application on any platform. A trailing newline does
/// not produce an empty last row - spreadsheets add one - but an empty line
/// in the middle does, since that is a row of blanks the user copied.
///
/// Quoted fields are understood, RFC 4180 style: a field wrapped in double
/// quotes may contain the delimiter, a newline, or a doubled `""` quote.
/// Excel, Sheets and LibreOffice all quote such a cell, and reading the text
/// literally split one cell containing a line break into two rows.
List<List<String>> parseClipboardText(String text, {String delimiter = '\t'}) {
  if (text.isEmpty) return const [];
  // A trailing line break is punctuation - spreadsheets add one - so it is
  // taken off before parsing rather than becoming a row of one empty cell.
  final body = text.endsWith('\r\n')
      ? text.substring(0, text.length - 2)
      : (text.endsWith('\n') || text.endsWith('\r')
          ? text.substring(0, text.length - 1)
          : text);
  if (body.isEmpty) return const [];
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  while (i < body.length) {
    final char = body[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < body.length && body[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        quoted = false;
        i++;
        continue;
      }
      field.write(char);
      i++;
      continue;
    }
    if (char == '"' && field.isEmpty) {
      quoted = true;
      i++;
      continue;
    }
    if (delimiter.isNotEmpty && body.startsWith(delimiter, i)) {
      endField();
      i += delimiter.length;
      continue;
    }
    if (char == '\r' || char == '\n') {
      endRow();
      i += char == '\r' && i + 1 < body.length && body[i + 1] == '\n' ? 2 : 1;
      continue;
    }
    field.write(char);
    i++;
  }
  endRow();
  return rows;
}

/// Serialises a cell range as tab-separated text, the format spreadsheets and
/// most editors accept from the clipboard.
///
/// A cell containing the delimiter, a line break or a quote is wrapped in
/// quotes with its own quotes doubled, which is what a spreadsheet does and
/// what [parseClipboardText] reads back. Writing such a cell literally made
/// one cell holding two lines paste as two rows.
///
/// Sanitises formulas by default for the same reason the CSV exporter does:
/// pasting a copied range into a spreadsheet is exactly the path
/// [CsvExporter.isFormula] guards against.
String toClipboardText<T>(
  List<List<String>> cells, {
  String delimiter = '\t',
  bool sanitizeFormulas = true,
  String formulaPrefix = "'",
}) {
  String cell(String value) {
    final sanitised = sanitizeFormulas && CsvExporter.isFormula(value)
        ? '$formulaPrefix$value'
        : value;
    final needsQuotes = sanitised.contains('"') ||
        sanitised.contains('\n') ||
        sanitised.contains('\r') ||
        (delimiter.isNotEmpty && sanitised.contains(delimiter));
    if (!needsQuotes) return sanitised;
    return '"${sanitised.replaceAll('"', '""')}"';
  }

  return cells.map((row) => row.map(cell).join(delimiter)).join('\n');
}
