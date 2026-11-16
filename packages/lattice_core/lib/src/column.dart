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
    this.sortKey,
  })  : title = title ?? _humanize(field),
        value = value ?? _mapGetter<T>(field),
        _usesDefaultValue = value == null,
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

  /// Reads the value this column *sorts and groups by*, when that differs
  /// from the value it shows.
  ///
  /// Returned once per row per sort rather than on every comparison, which is
  /// what makes an expensive ordering affordable: a natural order, a locale
  /// collation key or an enum rank costs O(n) here instead of O(n log n)
  /// inside [comparator]. Return a [String], a [num] or any value
  /// [compareValues] understands.
  ///
  /// Takes precedence over [comparator] when both are set, because a key is
  /// strictly the cheaper way to say the same thing.
  final Object? Function(T row)? sortKey;

  /// Whether [value] is the generated Map accessor rather than one the caller
  /// passed, so [copyWith] knows it may regenerate it for a new field.
  final bool _usesDefaultValue;

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

  /// The value this column orders by: [sortKey] when one is set, and the
  /// displayed value otherwise.
  Object? sortValue(T row) => sortKey == null ? value(row) : sortKey!(row);

  /// Clamps [candidate] into this column's allowed width range.
  double clampWidth(double candidate) => candidate.clamp(minWidth, maxWidth);

  /// A copy of this column with the given fields replaced.
  ///
  /// A `null` argument means "keep what is there", which is why every
  /// nullable field has a `clear` flag beside it: without one there was no
  /// way to *remove* a callback, so a column with a `setValue` could never be
  /// made read-only and a rule could never be taken off a column.
  ///
  /// Changing [field] also regenerates the default `Map` accessor, so a
  /// column declared without a `value:` reads the new field rather than
  /// quietly keeping the old one.
  GridColumn<T> copyWith({
    String? field,
    String? title,
    ValueGetter<T>? value,
    ColumnType? type,
    double? width,
    double? minWidth,
    double? maxWidth,
    ColumnAlign? align,
    bool clearAlign = false,
    ColumnPin? pin,
    bool? visible,
    bool? sortable,
    bool? filterable,
    bool? resizable,
    bool? groupable,
    ValueFormatter? format,
    bool clearFormat = false,
    Comparator<Object?>? comparator,
    bool clearComparator = false,
    ValueSetter<T>? setValue,
    bool clearSetValue = false,
    ValueValidator? validator,
    bool clearValidator = false,
    String? tooltip,
    bool clearTooltip = false,
    CellRule? rule,
    bool clearRule = false,
    Object? Function(T row)? sortKey,
    bool clearSortKey = false,
  }) {
    final nextField = field ?? this.field;
    // A column that never had an accessor of its own reads whichever field it
    // now names; one that was given an accessor keeps it.
    final nextValue = value ??
        (_usesDefaultValue && nextField != this.field ? null : this.value);
    return GridColumn<T>(
      field: nextField,
      title: title ?? this.title,
      value: nextValue,
      type: type ?? this.type,
      width: width ?? this.width,
      minWidth: minWidth ?? this.minWidth,
      maxWidth: maxWidth ?? this.maxWidth,
      align: clearAlign ? null : (align ?? this.align),
      pin: pin ?? this.pin,
      visible: visible ?? this.visible,
      sortable: sortable ?? this.sortable,
      filterable: filterable ?? this.filterable,
      resizable: resizable ?? this.resizable,
      groupable: groupable ?? this.groupable,
      format: clearFormat ? null : (format ?? this.format),
      comparator: clearComparator ? null : (comparator ?? this.comparator),
      setValue: clearSetValue ? null : (setValue ?? this.setValue),
      validator: clearValidator ? null : (validator ?? this.validator),
      tooltip: clearTooltip ? null : (tooltip ?? this.tooltip),
      rule: clearRule ? null : (rule ?? this.rule),
      sortKey: clearSortKey ? null : (sortKey ?? this.sortKey),
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

  /// `unitPrice` / `unit_price` / `unit-price` -> `Unit Price`, and
  /// `HTTPStatus` -> `HTTP Status`.
  ///
  /// An acronym stays whole: splitting on every case change would have
  /// produced `H T T P Status`, and splitting only after a lower-case letter
  /// produced `HTTPStatus`. The boundary that matters is the last capital of
  /// a run, which begins the next word.
  static String _humanize(String field) {
    final spaced = field
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
        .replaceAllMapped(RegExp(r'(?<=[A-Z])(?=[A-Z][a-z])'), (_) => ' ')
        .trim();
    if (spaced.isEmpty) return field;
    return spaced
        .split(RegExp(r'\s+'))
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
