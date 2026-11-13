/// Cell editing: an explicit begin / validate / commit state machine.
library;

import 'column.dart';
import 'selection.dart';

/// Why an edit session ended.
enum EditOutcome { committed, cancelled, rejected }

/// The result of trying to commit an edit.
class EditResult<T> {
  const EditResult._(this.outcome, {this.row, this.error});

  const EditResult.committed(T row) : this._(EditOutcome.committed, row: row);
  const EditResult.cancelled() : this._(EditOutcome.cancelled);
  const EditResult.rejected(String error)
      : this._(EditOutcome.rejected, error: error);

  final EditOutcome outcome;

  /// The row after the edit; null unless the edit committed.
  final T? row;

  /// Validation message; null unless the edit was rejected.
  final String? error;

  bool get isCommitted => outcome == EditOutcome.committed;
  bool get isRejected => outcome == EditOutcome.rejected;
}

/// One in-flight cell edit.
///
/// Editing is a session rather than a callback so that a half-typed value can
/// be validated, shown as an error, and either committed or rolled back
/// without the underlying row ever holding an invalid value.
class EditSession<T> {
  EditSession({
    required this.cell,
    required this.column,
    required this.row,
    required Object? initialValue,
  })  : _value = initialValue,
        originalValue = initialValue;

  final CellAddress cell;
  final GridColumn<T> column;

  /// The row being edited.
  final T row;

  /// Value when the session opened, restored by [cancel].
  final Object? originalValue;

  Object? _value;
  String? _error;

  /// The candidate value, as edited so far.
  Object? get value => _value;

  /// Current validation message, if any.
  String? get error => _error;

  bool get isValid => _error == null;

  bool get isDirty => _value != originalValue;

  /// Updates the candidate value and re-runs validation.
  ///
  /// Validating on change rather than on commit lets the editor show the error
  /// while the user is still typing.
  void update(Object? value) {
    _value = value;
    _error = column.validator?.call(value);
  }

  /// Validates and writes the value back through the column's setter.
  EditResult<T> commit() {
    final error = column.validator?.call(_value);
    if (error != null) {
      _error = error;
      return EditResult<T>.rejected(error);
    }
    final setValue = column.setValue;
    if (setValue == null) {
      return EditResult<T>.rejected('Column is not editable');
    }
    final updated = setValue(row, _value);
    // A null return means the model mutated in place.
    return EditResult<T>.committed(updated ?? row);
  }

  EditResult<T> cancel() {
    _value = originalValue;
    _error = null;
    return EditResult<T>.cancelled();
  }
}

/// Parses editor text back into the column's value type.
///
/// Editors hand back strings; a number column must not silently store `"42"`
/// where every comparator expects a [num].
Object? coerceValue(String text, ColumnType type) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  switch (type) {
    case ColumnType.number:
      return num.tryParse(trimmed);
    case ColumnType.boolean:
      final lower = trimmed.toLowerCase();
      if (lower == 'true' || lower == 'yes' || lower == '1') return true;
      if (lower == 'false' || lower == 'no' || lower == '0') return false;
      return null;
    case ColumnType.date:
      return DateTime.tryParse(trimmed);
    case ColumnType.text:
    case ColumnType.custom:
      return text;
  }
}

/// Builds a validator that rejects empty values.
ValueValidator requiredValue([String message = 'Required']) {
  return (Object? value) {
    if (value == null) return message;
    if (value is String && value.trim().isEmpty) return message;
    return null;
  };
}

/// Builds a validator bounding a numeric column.
ValueValidator numberRange({num? min, num? max, String? message}) {
  return (Object? value) {
    if (value == null) return null;
    if (value is! num) return message ?? 'Must be a number';
    if (min != null && value < min) return message ?? 'Must be at least $min';
    if (max != null && value > max) return message ?? 'Must be at most $max';
    return null;
  };
}

/// Composes validators, reporting the first failure.
ValueValidator allOf(List<ValueValidator> validators) {
  return (Object? value) {
    for (final validator in validators) {
      final error = validator(value);
      if (error != null) return error;
    }
    return null;
  };
}
