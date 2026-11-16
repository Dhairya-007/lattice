// Remote-write and undo fixes from the 0.4.0 review.
import 'dart:async';

import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// A remote source: rows in memory, writes that resolve when told to.
class _Backend extends LatticeDataSource<Product> {
  _Backend(this.rows);

  final List<Product> rows;
  final List<Completer<void>> gates = [];
  bool refuse = false;

  @override
  bool get canCommit => true;

  @override
  Future<GridResult<Product>> fetch(GridQuery query) async =>
      GridResult<Product>(
        rows: List<Product>.of(rows),
        totalCount: rows.length,
        filteredCount: rows.length,
      );

  @override
  Future<Product> commit(Product original, Product updated) async {
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    if (refuse) throw StateError('the server said no');
    return updated;
  }
}

GridController<Product> _remoteGrid(_Backend backend) =>
    GridController<Product>(
      columns: productColumns(),
      dataSource: backend,
      rowKey: (p) => p.id,
    );

void main() {
  group('two writes to one row', () {
    test('the finishing write does not wipe the newer one', () async {
      final backend = _Backend([
        Product(id: 1, name: 'first-ish', category: 'c', price: 1),
      ]);
      final grid = _remoteGrid(backend);
      await grid.refresh();

      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('first');
      grid.commitEdit();
      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('second');
      grid.commitEdit();

      expect(grid.dataAt(0)!.name, 'second');

      // The first write lands while the second is still in flight.
      backend.gates.first.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        grid.dataAt(0)!.name,
        'second',
        reason: 'the newer write owns the cell',
      );
      grid.dispose();
    });
  });

  group('a refused write', () {
    test('puts the value back on a model that mutates in place', () async {
      final product = Product(id: 1, name: 'a', category: 'c', price: 80);
      final backend = _Backend([product])..refuse = true;
      final grid = _remoteGrid(backend);
      await grid.refresh();

      grid.beginEdit(const CellAddress(0, 'price'));
      grid.updateEdit(999);
      grid.commitEdit();
      expect(product.price, 999, reason: 'shown at once, optimistically');

      backend.gates.first.complete();
      await grid.pendingWrite;

      expect(grid.writeError, isA<StateError>());
      expect(product.price, 80, reason: 'the refused value must not stay');
      expect(grid.dataAt(0)!.price, 80);
      grid.dispose();
    });

    test('a refused local write puts the value back too', () async {
      final product = Product(id: 1, name: 'a', category: 'c', price: 80);
      final source = _RefusingLocal([product]);
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
        rowKey: (p) => p.id,
      );
      grid.beginEdit(const CellAddress(0, 'price'));
      grid.updateEdit(999);
      grid.commitEdit();
      await grid.pendingWrite;
      expect(grid.writeError, isNotNull);
      expect(product.price, 80);
      grid.dispose();
    });
  });

  group('committing an unchanged value', () {
    test('writes nothing and records no undo step', () async {
      final backend = _Backend([
        Product(id: 1, name: 'a', category: 'c', price: 1),
      ]);
      final grid = _remoteGrid(backend);
      await grid.refresh();

      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('a');
      grid.commitEdit();
      await Future<void>.delayed(Duration.zero);

      expect(backend.gates, isEmpty, reason: 'nothing to save');
      expect(grid.canUndo, isFalse);
      grid.dispose();
    });
  });

  group('undo', () {
    test('restores every row a paste touched, in view or not', () {
      final products = [
        Product(id: 1, name: 'Keyboard', category: 'Input', price: 1),
        Product(id: 2, name: 'Mouse', category: 'Input', price: 2),
      ];
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: InMemoryDataSource<Product>(products),
        rowKey: (p) => p.id,
      );
      grid.pasteText('K2\nM2', at: const CellAddress(0, 'name'));
      expect([for (final p in products) p.name], ['K2', 'M2']);

      grid.setSearch('M2');
      expect(grid.rowCount, 1);
      expect(grid.undo(), isTrue);
      expect(grid.lastReplay.isComplete, isTrue);

      grid.setSearch('');
      expect([for (final p in products) p.name], ['Keyboard', 'Mouse']);
      grid.dispose();
    });

    test('an undo that cannot be applied keeps its step', () async {
      final backend = _Backend([
        Product(id: 1, name: 'a', category: 'c', price: 1),
      ]);
      final grid = _remoteGrid(backend);
      await grid.refresh();
      grid.beginEdit(const CellAddress(0, 'name'));
      grid.updateEdit('b');
      grid.commitEdit();
      backend.gates.first.complete();
      await grid.pendingWrite;

      // A remote source cannot enumerate its rows, so emptying the view
      // leaves undo nothing to resolve against.
      backend.rows.clear();
      await grid.refresh();

      expect(grid.undo(), isFalse);
      expect(grid.canUndo, isTrue, reason: 'the step is still there');
      expect(grid.canRedo, isFalse);
      expect(grid.lastReplay.unresolved, 1);
      grid.dispose();
    });
  });
}

/// A local source that refuses every write.
class _RefusingLocal extends InMemoryDataSource<Product> {
  _RefusingLocal(super.rows);

  @override
  Future<List<Product>> commitAll(List<RowUpdate<Product>> writes) async =>
      throw StateError('read-only today');
}
