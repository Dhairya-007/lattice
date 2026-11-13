/// Column definition and supporting value types.
library;

import 'decoration.dart';

/// Horizontal alignment of a cell's content.
enum ColumnAlign { start, center, end }

/// Which edge of the viewport a column is frozen to, if any.
enum ColumnPin { none, start, end }

/// Logical type of a column's values.
///
/// Drives default comparators, the default set of filter operators offered to
/// the user, and the editor a UI adapter picks for the column.
enum ColumnType { text, number, boolean, date, custom }

/// Reads the value of a column out of a row object.
typedef ValueGetter<T> = Object? Function(T row);

/// Writes an edited value back into a row object.
///
/// Returning a value lets immutable models return a modified copy; returning
/// `null` means the row was mutated in place.
typedef ValueSetter<T> = T? Function(T row, Object? value);

/// Renders a raw value as display text.
typedef ValueFormatter = String Function(Object? value);

/// Validates a candidate value, returning an error message or `null` if valid.
typedef ValueValidator = String? Function(Object? value);

/// Describes one column of a grid.
///
/// A column is pure data: it knows how to read a value out of a row, how to
/// show it, how to compare it and whether the user may sort, filter, resize or
/// edit it. It holds no rendering logic, so the same definition can drive the
/// Flutter adapter or any future web adapter.
class GridColumn<T> {
  GridColumn({
    required this.field,
    String? title,
    ValueGetter<T>? value,
    this.type = ColumnType.text,
    this.width = 140,
    this.minWidth = 48,
    this.maxWidth = 1200,
    this.align,
    this.pin = ColumnPin.none,
    this.visible = true,
    this.sortable = true,
    this.filterable = true,
    this.resizable = true,
    this.groupable = true,
    this.format,
    this.comparator,
    this.setValue,
    this.validator,
    this.tooltip,
    this.rule,
  })  : title = title ?? _humanize(field),
        value = value ?? _mapGetter<T>(field),
        assert(minWidth <= maxWidth, 'minWidth must not exceed maxWidth'),
        assert(width > 0, 'width must be positive');

  /// Stable identifier for the column, unique within a grid.
  ///
  /// Also used as the default key when reading from `Map` rows and as the
  /// header of exported files.
  final String field;

  /// Header text.
  final String title;

  /// Reads this column's value out of a row.
  final ValueGetter<T> value;

  /// Logical value type.
  final ColumnType type;

  /// Preferred width in logical pixels, before resizing or stretching.
  final double width;

  /// Lower bound honoured by interactive resizing.
  final double minWidth;

  /// Upper bound honoured by interactive resizing.
  final double maxWidth;

  /// Content alignment; defaults to [ColumnAlign.end] for numbers.
  final ColumnAlign? align;

  /// Edge this column is frozen to.
  final ColumnPin pin;

  /// Whether the column takes part in layout at all.
  final bool visible;

  final bool sortable;
  final bool filterable;
  final bool resizable;
  final bool groupable;

  /// Formats the raw value for display. Defaults to [Object.toString].
  final ValueFormatter? format;

  /// Overrides the default ordering for this column's values.
  final Comparator<Object?>? comparator;

  /// Writes an edited value back. A column is editable when this is non-null.
  final ValueSetter<T>? setValue;

  /// Rejects invalid edits before they are committed.
  final ValueValidator? validator;

  /// Long-form description for a header tooltip.
  final String? tooltip;

  /// Conditional formatting for this column's cells.
  ///
  /// Evaluated per visible cell against the column's [ColumnStats], so it
  /// costs nothing for rows that are not on screen.
  final CellRule? rule;

  /// Whether the user may edit cells in this column.
  bool get editable => setValue != null;

  /// Effective alignment, resolving the type-based default.
  ColumnAlign get effectiveAlign =>
      align ??
      (type == ColumnType.number ? ColumnAlign.end : ColumnAlign.start);

  /// Display text for [row] in this column.
  String formattedValue(T row) {
    final raw = value(row);
    if (format != null) return format!(raw);
    return raw == null ? '' : '$raw';
  }

  /// Clamps [candidate] into this column's allowed width range.
  double clampWidth(double candidate) => candidate.clamp(minWidth, maxWidth);

  GridColumn<T> copyWith({
    String? field,
    String? title,
    ValueGetter<T>? value,
    ColumnType? type,
    double? width,
    double? minWidth,
    double? maxWidth,
    ColumnAlign? align,
    ColumnPin? pin,
    bool? visible,
    bool? sortable,
    bool? filterable,
    bool? resizable,
    bool? groupable,
    ValueFormatter? format,
    Comparator<Object?>? comparator,
    ValueSetter<T>? setValue,
    ValueValidator? validator,
    String? tooltip,
    CellRule? rule,
  }) {
    return GridColumn<T>(
      field: field ?? this.field,
      title: title ?? this.title,
      value: value ?? this.value,
      type: type ?? this.type,
      width: width ?? this.width,
      minWidth: minWidth ?? this.minWidth,
      maxWidth: maxWidth ?? this.maxWidth,
      align: align ?? this.align,
      pin: pin ?? this.pin,
      visible: visible ?? this.visible,
      sortable: sortable ?? this.sortable,
      filterable: filterable ?? this.filterable,
      resizable: resizable ?? this.resizable,
      groupable: groupable ?? this.groupable,
      format: format ?? this.format,
      comparator: comparator ?? this.comparator,
      setValue: setValue ?? this.setValue,
      validator: validator ?? this.validator,
      tooltip: tooltip ?? this.tooltip,
      rule: rule ?? this.rule,
    );
  }

  @override
  String toString() => 'GridColumn($field)';

  static ValueGetter<T> _mapGetter<T>(String field) {
    return (T row) {
      if (row is Map) return row[field];
      throw StateError(
        'GridColumn("$field") has no value accessor and rows of type $T are '
        'not Map-like. Pass `value:` when defining the column.',
      );
    };
  }

  /// `unitPrice` / `unit_price` / `unit-price` -> `Unit Price`.
  static String _humanize(String field) {
    final spaced = field
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
        .trim();
    if (spaced.isEmpty) return field;
    return spaced
        .split(RegExp(r'\s+'))
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
