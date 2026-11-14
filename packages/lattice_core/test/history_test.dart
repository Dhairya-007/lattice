import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

GridController<Product> editGrid() {
  final columns = productColumns();
  return GridController<Product>(
    columns: [columns[0], columns[2], columns[3]],
    dataSource: InMemoryDataSource<Product>(sampleProducts()),
    rowKey: (p) => p.id,
  );
}

void main() {
  group('EditHistory', () {
    test('records actions and reports what the next step would be', () {
      final history = EditHistory<Product>();
      expect(history.canUndo, isFalse);
      expect(history.undoLabel, isNull);

      history.record(EditAction<Product>(
        label: 'Edit Name',
        changes: [
          CellEdit<Product>(
            row: sampleProducts().first,
            field: 'name',
            before: 'a',
            after: 'b',
          ),
        ],
      ));
      expect(history.canUndo, isTrue);
      expect(history.undoLabel, 'Edit Name');
    });

    test('an empty action is not worth a step', () {
      final history = EditHistory<Product>()
        ..record(const EditAction<Product>(label: 'Nothing', changes: []));
      expect(history.canUndo, isFalse);
    });

    test('drops the oldest action past its limit', () {
      final history = EditHistory<Product>(limit: 2);
      for (var i = 0; i < 5; i++) {
        history.record(EditAction<Product>(
          label: 'Edit $i',
          changes: [
            CellEdit<Product>(
              row: sampleProducts().first,
              field: 'name',
              before: i,
              after: i + 1,
            ),
          ],
        ));
      }
      expect(history.length, 2);
      expect(history.undoLabel, 'Edit 4');
    });

    test('editing again makes the undone future unreachable', () {
      final history = EditHistory<Product>();
      CellEdit<Product> change(int i) => CellEdit<Product>(
            row: sampleProducts().first,
            field: 'name',
            before: i,
            after: i + 1,
          );
      history.record(
        EditAction<Product>(label: 'one', changes: [change(1)]),
      );
      history.takeUndo();
      expect(history.canRedo, isTrue);
      history.record(
        EditAction<Product>(label: 'two', changes: [change(2)]),
      );
      expect(history.canRedo, isFalse);
    });

    test('an inverse action replays the cells backwards', () {
      final row = sampleProducts().first;
      final action = EditAction<Product>(
        label: 'Paste',
        changes: [
          CellEdit<Product>(row: row, field: 'name', before: 'a', after: 'b'),
          CellEdit<Product>(row: row, field: 'price', before: 1, after: 2),
        ],
      );
      final inverse = action.inverse;
      expect(inverse.changes.first.field, 'price');
      expect(inverse.changes.first.before, 2);
      expect(inverse.changes.first.after, 1);
    });
  });

  group('undo over a committed edit', () {
    test('puts the old value back', () {
      final grid = editGrid();
      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('Keypad');
      grid.commitEdit();
      expect(grid.dataAt(0)!.name, 'Keypad');

      expect(grid.canUndo, isTrue);
      expect(grid.undo(), isTrue);
      expect(grid.dataAt(0)!.name, 'Keyboard');
    });

    test('redo puts the new one back again', () {
      final grid = editGrid();
      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('Keypad');
      grid.commitEdit();
      grid.undo();
      expect(grid.canRedo, isTrue);
      expect(grid.redo(), isTrue);
      expect(grid.dataAt(0)!.name, 'Keypad');
    });

    test('an edit that changed nothing is not a step', () {
      final grid = editGrid();
      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('Keyboard');
      grid.commitEdit();
      expect(grid.canUndo, isFalse);
    });

    test('a rejected edit is not a step either', () {
      final grid = editGrid();
      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('');
      grid.commitEdit();
      expect(grid.canUndo, isFalse);
    });

    test('with nothing to undo, undo says so instead of throwing', () {
      final grid = editGrid();
      expect(grid.undo(), isFalse);
      expect(grid.redo(), isFalse);
    });

    test('the label names what will be taken back', () {
      final grid = editGrid();
      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('Keypad');
      grid.commitEdit();
      expect(grid.history.undoLabel, 'Edit Name');
    });
  });

  group('undo over a paste', () {
    test('a whole block comes back in one step', () {
      final grid = editGrid();
      grid.pasteText(
        'Keypad\t10\nTrackball\t20',
        at: const CellAddress(0, 'name'),
      );
      expect(grid.dataAt(0)!.name, 'Keypad');
      expect(grid.dataAt(1)!.price, 20);

      expect(grid.undo(), isTrue);
      expect(grid.dataAt(0)!.name, 'Keyboard');
      expect(grid.dataAt(0)!.price, 80);
      expect(grid.dataAt(1)!.name, 'Mouse');
      expect(grid.dataAt(1)!.price, 25);
      expect(grid.canUndo, isFalse);
    });

    test('and goes back in one step too', () {
      final grid = editGrid();
      grid.pasteText('Keypad\t10', at: const CellAddress(0, 'name'));
      grid.undo();
      grid.redo();
      expect(grid.dataAt(0)!.name, 'Keypad');
      expect(grid.dataAt(0)!.price, 10);
    });

    test('a paste that wrote nothing leaves no step to undo', () {
      final grid = editGrid();
      grid.pasteText('Keypad\tnope', at: const CellAddress(0, 'name'));
      expect(grid.canUndo, isFalse);
    });

    test('undo finds its rows after a sort has moved them', () {
      final grid = editGrid();
      grid.pasteText('Zebra', at: const CellAddress(0, 'name'));
      grid.setSorts([const SortSpec('name')]);
      expect(labelsOf(grid).last, 'Zebra');
      expect(grid.undo(), isTrue);
      expect(labelsOf(grid), contains('Keyboard'));
      expect(labelsOf(grid), isNot(contains('Zebra')));
    });

    test('undo cannot reach a row that is no longer in view', () {
      final grid = editGrid();
      grid.pasteText('Zebra', at: const CellAddress(0, 'name'));
      grid.setSearch('mouse');
      expect(grid.undo(), isFalse);
    });
  });
}
