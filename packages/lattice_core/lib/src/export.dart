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
    if (options.includeHeader) {
      out.write(_line([for (final c in exported) c.title]));
    }
    for (final row in rows) {
      out.write(_line([for (final c in exported) _cell(c, row)]));
    }
    return out.toString();
  }

  /// Exports a grouped result, writing one indented header line per group.
  String exportGroups(
      List<GroupNode<T>> groups, GroupExpansionState expansion) {
    final out = StringBuffer();
    final exported = _exported;
    if (options.includeHeader) {
      out.write(_line([for (final c in exported) c.title]));
    }

    void walk(List<GroupNode<T>> level) {
      for (final node in level) {
        if (options.includeGroupRows) {
          final label = '${options.groupIndent * node.depth}'
              '${node.label} (${node.rowCount})';
          out.write(_line([label, ...List.filled(exported.length - 1, '')]));
        }
        if (node.isLeafGroup) {
          for (final row in node.rows) {
            out.write(_line([
              for (final c in exported)
                '${options.groupIndent * (node.depth + 1)}${_cell(c, row)}',
            ]));
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

  String _line(List<String> cells) =>
      '${cells.map(_escape).join(options.delimiter)}${options.lineEnding}';

  /// RFC 4180 quoting: wrap in quotes when the value contains the delimiter, a
  /// quote or a newline, and double any embedded quotes.
  String _escape(String value) {
    final needsQuotes = value.contains(options.delimiter) ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}

/// Serialises a cell range as tab-separated text, the format spreadsheets and
/// most editors accept from the clipboard.
String toClipboardText<T>(
  List<List<String>> cells, {
  String delimiter = '\t',
}) {
  return cells.map((row) => row.join(delimiter)).join('\n');
}
