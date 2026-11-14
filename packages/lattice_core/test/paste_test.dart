import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// name, price, stock, active - two editable columns side by side, which is
/// what a pasted block needs to land in.
GridController<Product> pasteGrid({
  SelectionMode selectionMode = SelectionMode.multiRow,
}) {
  final columns = productColumns();
  return GridController<Product>(
    columns: [columns[0], columns[2], columns[3], columns[4]],
    dataSource: InMemoryDataSource<Product>(sampleProducts()),
    selectionMode: selectionMode,
  );
}

void main() {
  group('parseClipboardText', () {
    test('splits rows and cells', () {
      expect(parseClipboardText('a\tb\nc\td'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('accepts any line ending a clipboard can carry', () {
      expect(parseClipboardText('a\r\nb\rc\nd').length, 4);
    });

    test('ignores one trailing newline but keeps an empty row in the middle',
        () {
      expect(parseClipboardText('a\nb\n').length, 2);
      expect(parseClipboardText('a\n\nb'), [
        ['a'],
        [''],
        ['b'],
      ]);
    });

    test('is the inverse of toClipboardText', () {
      const cells = [
        ['a', 'b'],
        ['c', 'd'],
      ];
      expect(parseClipboardText(toClipboardText<Product>(cells)), cells);
    });

    test('empty text is no rows at all', () {
      expect(parseClipboardText(''), isEmpty);
      expect(parseClipboardText('\n'), isEmpty);
    });
  });

  group('pasteText', () {
    test('writes a block rightwards and downwards from the target', () {
      final grid = pasteGrid();
      final result = grid.pasteText(
        'Keypad\t10\nTrackball\t20',
        at: const CellAddress(0, 'name'),
      );
      expect(result.applied, isTrue);
      expect(result.rowsChanged, 2);
      expect(result.cellsChanged, 4);
      expect(grid.dataAt(0)!.name, 'Keypad');
      expect(grid.dataAt(0)!.price, 10);
      expect(grid.dataAt(1)!.name, 'Trackball');
      expect(grid.dataAt(1)!.price, 20);
    });

    test('pastes into the active cell when no target is given', () {
      final grid = pasteGrid(selectionMode: SelectionMode.cellRange);
      grid.selectCell(const CellAddress(1, 'name'));
      grid.pasteText('Trackpad');
      expect(grid.dataAt(1)!.name, 'Trackpad');
    });

    test('with nowhere to paste, does nothing and says so', () {
      final grid = pasteGrid();
      final result = grid.pasteText('x');
      expect(result.applied, isFalse);
      expect(result.isEmpty, isTrue);
    });

    test('coerces each cell into its column type', () {
      final grid = pasteGrid();
      grid.pasteText('40', at: const CellAddress(0, 'price'));
      expect(grid.dataAt(0)!.price, 40);
      expect(grid.dataAt(0)!.price, isA<num>());
    });

    test('one bad cell writes nothing at all', () {
      final grid = pasteGrid();
      final before = grid.dataAt(0)!.name;
      final result = grid.pasteText(
        'Keypad\tnot-a-number',
        at: const CellAddress(0, 'name'),
      );
      expect(result.applied, isFalse);
      expect(result.rejections.single.reason, 'Not a number');
      expect(result.rejections.single.cell.field, 'price');
      expect(grid.dataAt(0)!.name, before);
    });

    test('with allOrNothing off, writes what it can and reports the rest', () {
      final grid = pasteGrid();
      final result = grid.pasteText(
        'Keypad\tnot-a-number',
        at: const CellAddress(0, 'name'),
        allOrNothing: false,
      );
      expect(result.applied, isTrue);
      expect(result.cellsChanged, 1);
      expect(result.rejections.length, 1);
      expect(grid.dataAt(0)!.name, 'Keypad');
    });

    test('a value the column validator rejects is reported in its words', () {
      final grid = pasteGrid();
      final result = grid.pasteText('-5', at: const CellAddress(0, 'price'));
      expect(result.rejections.single.reason, 'Must be at least 0');
    });

    test('a read-only column is rejected, not silently skipped', () {
      final grid = pasteGrid();
      final result = grid.pasteText('99', at: const CellAddress(0, 'stock'));
      expect(result.rejections.single.reason, 'Column is not editable');
    });

    test('a block past the end of the grid is clipped, not grown', () {
      final grid = pasteGrid();
      final result = grid.pasteText(
        'a\nb\nc',
        at: const CellAddress(5, 'name'),
        allOrNothing: false,
      );
      expect(grid.rowCount, 6);
      expect(result.rowsChanged, 1);
      expect(result.cellsClipped, 2);
    });

    test('a block past the last column is clipped too', () {
      final grid = pasteGrid();
      final result = grid.pasteText(
        'x\ty\tz',
        at: const CellAddress(0, 'active'),
        allOrNothing: false,
      );
      expect(result.cellsClipped, 2);
    });

    test('follows screen order, so a pinned column is pasted where it looks',
        () {
      final grid = pasteGrid();
      grid.setColumnPin('price', ColumnPin.start);
      grid.pasteText('5\tKeypad', at: const CellAddress(0, 'price'));
      expect(grid.dataAt(0)!.price, 5);
      expect(grid.dataAt(0)!.name, 'Keypad');
    });

    test('a value equal to the one already there is not a change', () {
      final grid = pasteGrid();
      final result = grid.pasteText(
        'Keyboard',
        at: const CellAddress(0, 'name'),
      );
      expect(result.cellsChanged, 0);
      expect(result.applied, isFalse);
    });

    test('a source that cannot save refuses the paste', () async {
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: AsyncDataSource<Product>(
          (q) async =>
              GridResult<Product>(rows: sampleProducts(), totalCount: 6),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final result = grid.pasteText('x', at: const CellAddress(0, 'name'));
      expect(result.applied, isFalse);
      expect(result.rejections.single.reason, contains('cannot save edits'));
    });

    test('several cells in one row are written as one change', () {
      var writes = 0;
      final source = CountingSource(sampleProducts(), onWrite: () => writes++);
      final columns = productColumns();
      final grid = GridController<Product>(
        columns: [columns[0], columns[2]],
        dataSource: source,
      );
      grid.pasteText('Keypad\t10', at: const CellAddress(0, 'name'));
      expect(writes, 1);
    });
  });
}

/// Counts how many batches reach the source, so a paste can be shown to be
/// one write rather than one per cell.
class CountingSource extends InMemoryDataSource<Product> {
  CountingSource(super.rows, {required this.onWrite});

  final void Function() onWrite;

  @override
  Future<List<Product>> commitAll(List<RowUpdate<Product>> writes) {
    onWrite();
    return super.commitAll(writes);
  }
}
