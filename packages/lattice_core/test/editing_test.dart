import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  Product product() =>
      Product(id: 1, name: 'Keyboard', category: 'Input', price: 80, stock: 12);

  EditSession<Product> session(String field, Product row) {
    final column = productColumnMap()[field]!;
    return EditSession<Product>(
      cell: CellAddress(0, field),
      column: column,
      row: row,
      initialValue: column.value(row),
    );
  }

  group('EditSession', () {
    test('starts clean on the current value', () {
      final edit = session('name', product());
      expect(edit.value, 'Keyboard');
      expect(edit.originalValue, 'Keyboard');
      expect(edit.isDirty, isFalse);
      expect(edit.isValid, isTrue);
    });

    test('tracks dirtiness as the user types', () {
      final edit = session('name', product());
      edit.update('Keypad');
      expect(edit.isDirty, isTrue);
      edit.update('Keyboard');
      expect(edit.isDirty, isFalse);
    });

    test('validates on change, not only on commit', () {
      final edit = session('name', product());
      edit.update('');
      expect(edit.error, 'Required');
      expect(edit.isValid, isFalse);
    });

    test('a valid commit writes through to the row', () {
      final row = product();
      final edit = session('name', row);
      edit.update('Keypad');
      final result = edit.commit();
      expect(result.isCommitted, isTrue);
      expect(result.row!.name, 'Keypad');
      expect(row.name, 'Keypad');
    });

    test('an invalid commit is rejected and leaves the row untouched', () {
      final row = product();
      final edit = session('name', row);
      edit.update('');
      final result = edit.commit();
      expect(result.isRejected, isTrue);
      expect(result.error, 'Required');
      expect(result.row, isNull);
      expect(row.name, 'Keyboard');
    });

    test('a rejected commit keeps the typed value so it can be corrected', () {
      final edit = session('price', product());
      edit.update(-5);
      expect(edit.commit().isRejected, isTrue);
      expect(edit.value, -5);
      edit.update(10);
      expect(edit.commit().isCommitted, isTrue);
    });

    test('cancel restores the original value', () {
      final row = product();
      final edit = session('name', row);
      edit.update('Nonsense');
      final result = edit.cancel();
      expect(result.outcome, EditOutcome.cancelled);
      expect(edit.value, 'Keyboard');
      expect(edit.error, isNull);
      expect(row.name, 'Keyboard');
    });

    test('a column without a setter cannot be committed', () {
      final edit = session('category', product());
      edit.update('Other');
      final result = edit.commit();
      expect(result.isRejected, isTrue);
      expect(result.error, 'Column is not editable');
    });
  });

  group('coerceValue', () {
    test('parses numbers and rejects nonsense', () {
      expect(coerceValue('42', ColumnType.number), 42);
      expect(coerceValue('3.5', ColumnType.number), 3.5);
      expect(coerceValue('abc', ColumnType.number), isNull);
    });

    test('parses the usual spellings of a boolean', () {
      expect(coerceValue('true', ColumnType.boolean), isTrue);
      expect(coerceValue('YES', ColumnType.boolean), isTrue);
      expect(coerceValue('1', ColumnType.boolean), isTrue);
      expect(coerceValue('no', ColumnType.boolean), isFalse);
      expect(coerceValue('0', ColumnType.boolean), isFalse);
      expect(coerceValue('maybe', ColumnType.boolean), isNull);
    });

    test('parses ISO dates', () {
      expect(coerceValue('2026-03-04', ColumnType.date), DateTime(2026, 3, 4));
      expect(coerceValue('not a date', ColumnType.date), isNull);
    });

    test('keeps text verbatim, including its whitespace', () {
      expect(coerceValue('  hello  ', ColumnType.text), '  hello  ');
    });

    test('blank text becomes null for every type', () {
      expect(coerceValue('   ', ColumnType.text), isNull);
      expect(coerceValue('', ColumnType.number), isNull);
    });
  });

  group('validators', () {
    test('requiredValue rejects null and blank text', () {
      final validate = requiredValue();
      expect(validate(null), 'Required');
      expect(validate('   '), 'Required');
      expect(validate('x'), isNull);
      expect(validate(0), isNull);
    });

    test('requiredValue takes a custom message', () {
      expect(requiredValue('Name needed')(null), 'Name needed');
    });

    test('numberRange bounds a value at both ends', () {
      final validate = numberRange(min: 0, max: 10);
      expect(validate(-1), isNotNull);
      expect(validate(11), isNotNull);
      expect(validate(5), isNull);
      expect(validate(0), isNull);
      expect(validate(10), isNull);
    });

    test('numberRange passes null through for a required check to catch', () {
      expect(numberRange(min: 0)(null), isNull);
    });

    test('numberRange rejects a non-number', () {
      expect(numberRange(min: 0)('abc'), 'Must be a number');
    });

    test('combineValidators reports the first failure', () {
      final validate = combineValidators([requiredValue(), numberRange(min: 10)]);
      expect(validate(null), 'Required');
      expect(validate(5), 'Must be at least 10');
      expect(validate(15), isNull);
    });
  });
}
