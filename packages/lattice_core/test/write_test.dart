import 'dart:async';

import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// An immutable row, which is what makes a lost write visible: an in-place
/// model would keep the new value whether or not the source stored it.
class Task {
  const Task(this.id, this.title);

  final int id;
  final String title;
}

List<GridColumn<Task>> taskColumns() => [
      GridColumn<Task>(
        field: 'title',
        value: (t) => t.title,
        setValue: (t, v) => Task(t.id, (v ?? '') as String),
      ),
      GridColumn<Task>(
          field: 'id', type: ColumnType.number, value: (t) => t.id),
    ];

/// A stand-in for a server: it hands out fresh instances on every fetch, so a
/// grid that does not track its write loses it.
class FakeBackend {
  FakeBackend(this.rows);

  List<Task> rows;
  int fetches = 0;
  Object? failWith;
  final List<Completer<void>> gates = [];

  AsyncDataSource<Task> source() => AsyncDataSource<Task>(
        (query) async {
          fetches++;
          return GridResult<Task>(
            rows: [for (final t in rows) Task(t.id, t.title)],
            totalCount: rows.length,
          );
        },
        onCommit: (original, updated) async {
          if (gates.isNotEmpty) await gates.removeAt(0).future;
          final failure = failWith;
          if (failure != null) throw failure;
          rows = [
            for (final t in rows) t.id == updated.id ? updated : t,
          ];
          return updated;
        },
      );
}

GridController<Task> taskGrid(FakeBackend backend) => GridController<Task>(
      columns: taskColumns(),
      dataSource: backend.source(),
      rowKey: (t) => t.id,
    );

void main() {
  group('a source that cannot write', () {
    test('refuses to open an editor rather than lose the value', () {
      final grid = GridController<Task>(
        columns: taskColumns(),
        dataSource: AsyncDataSource<Task>(
          (q) async => const GridResult<Task>(rows: [], totalCount: 0),
        ),
      );
      expect(grid.canEdit, isFalse);
      expect(grid.beginEdit(const CellAddress(0, 'title')), isNull);
    });

    test('an in-memory source can write, and says so', () {
      final grid = productGrid();
      expect(grid.canEdit, isTrue);
    });
  });

  group('committing to a remote source', () {
    test('the new value is on screen before the server confirms it', () async {
      final backend = FakeBackend([const Task(1, 'Write docs')]);
      final grid = taskGrid(backend);
      await Future<void>.delayed(Duration.zero);

      final gate = Completer<void>();
      backend.gates.add(gate);
      grid.beginEdit(const CellAddress(0, 'title'));
      grid.updateEdit('Write better docs');
      expect(grid.commitEdit().isCommitted, isTrue);

      expect(grid.dataAt(0)!.title, 'Write better docs');
      expect(grid.hasPendingWrites, isTrue);

      gate.complete();
      await grid.pendingWrite;
      expect(grid.dataAt(0)!.title, 'Write better docs');
      expect(grid.hasPendingWrites, isFalse);
      expect(grid.writeError, isNull);
    });

    test('the re-fetch that follows a write cannot bring the old value back',
        () async {
      final backend = FakeBackend([const Task(1, 'a'), const Task(2, 'b')]);
      final grid = taskGrid(backend);
      await Future<void>.delayed(Duration.zero);
      final before = backend.fetches;

      grid.beginEdit(const CellAddress(1, 'title'));
      grid.updateEdit('b2');
      grid.commitEdit();
      await grid.pendingWrite;

      expect(backend.fetches, greaterThan(before));
      expect(grid.dataAt(1)!.title, 'b2');
      expect(backend.rows[1].title, 'b2');
    });

    test('a write the server refuses rolls back and reports why', () async {
      final backend = FakeBackend([const Task(1, 'a')])
        ..failWith = StateError('conflict');
      final grid = taskGrid(backend);
      await Future<void>.delayed(Duration.zero);

      grid.beginEdit(const CellAddress(0, 'title'));
      grid.updateEdit('a2');
      grid.commitEdit();
      expect(grid.dataAt(0)!.title, 'a2', reason: 'shown optimistically');

      await grid.pendingWrite;
      expect(grid.dataAt(0)!.title, 'a');
      expect(grid.writeError, isA<StateError>());
      expect(grid.hasPendingWrites, isFalse);

      grid.clearWriteError();
      expect(grid.writeError, isNull);
    });

    test('a rejected value keeps the session open and writes nothing',
        () async {
      final backend = FakeBackend([const Task(1, 'a')]);
      final grid = GridController<Task>(
        columns: [
          GridColumn<Task>(
            field: 'title',
            value: (t) => t.title,
            setValue: (t, v) => Task(t.id, (v ?? '') as String),
            validator: requiredValue(),
          ),
        ],
        dataSource: backend.source(),
        rowKey: (t) => t.id,
      );
      await Future<void>.delayed(Duration.zero);

      grid.beginEdit(const CellAddress(0, 'title'));
      grid.updateEdit('');
      final result = grid.commitEdit();
      expect(result.isRejected, isTrue);
      expect(grid.editSession, isNotNull);
      expect(grid.hasPendingWrites, isFalse);
      expect(backend.rows.single.title, 'a');
    });

    test('a value the source normalises is shown as the source stored it',
        () async {
      final rows = [const Task(1, 'a')];
      final source = AsyncDataSource<Task>(
        (q) async => GridResult<Task>(
          rows: [for (final t in rows) Task(t.id, t.title)],
          totalCount: rows.length,
        ),
        onCommit: (original, updated) async {
          final stored = Task(updated.id, updated.title.toUpperCase());
          rows[0] = stored;
          return stored;
        },
      );
      final grid = GridController<Task>(
        columns: taskColumns(),
        dataSource: source,
        rowKey: (t) => t.id,
      );
      await Future<void>.delayed(Duration.zero);

      grid.beginEdit(const CellAddress(0, 'title'));
      grid.updateEdit('shout');
      grid.commitEdit();
      await grid.pendingWrite;
      expect(grid.dataAt(0)!.title, 'SHOUT');
    });
  });

  group('committing to a local source', () {
    test('writes through and moves the row if the sort key changed', () {
      final grid = productGrid(sorts: [const SortSpec('name')]);
      expect(labelsOf(grid).first, 'Dock');
      grid.beginEdit(CellAddress(labelsOf(grid).indexOf('Webcam'), 'name'));
      grid.updateEdit('Aardvark');
      expect(grid.commitEdit().isCommitted, isTrue);
      expect(labelsOf(grid).first, 'Aardvark');
    });

    test('a row removed under the edit reports the failure', () async {
      final source = InMemoryDataSource<Product>(sampleProducts());
      final grid = GridController<Product>(
        columns: productColumns(),
        dataSource: source,
      );
      final target = source.rows[1];
      grid.beginEdit(const CellAddress(1, 'name'));
      grid.updateEdit('Gone');
      source.remove(target);
      grid.commitEdit();
      await grid.pendingWrite;
      expect(grid.writeError, isA<StateError>());
    });
  });
}
