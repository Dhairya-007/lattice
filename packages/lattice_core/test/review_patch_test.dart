// An edit patches the memoised pipeline instead of throwing it away.
//
// The patch is only worth having if it is indistinguishable from a full
// recompute, so that is what these tests check: the same rows, in the same
// order, as a source that has never cached anything would produce. A wrong
// answer here is a wrong grid, so the comparison is differential and
// randomised rather than a handful of cases somebody thought of.
import 'dart:math';

import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

class Row {
  Row(this.id, this.name, this.score, this.tag);

  final int id;
  String name;
  num? score;
  String tag;

  @override
  String toString() => 'Row($id, $name, $score, $tag)';
}

List<GridColumn<Row>> columns() => [
      GridColumn<Row>(field: 'id', type: ColumnType.number, value: (r) => r.id),
      GridColumn<Row>(field: 'name', value: (r) => r.name),
      GridColumn<Row>(
        field: 'score',
        type: ColumnType.number,
        value: (r) => r.score,
      ),
      GridColumn<Row>(field: 'tag', value: (r) => r.tag),
    ];

const _names = ['ada', 'Bo', 'cy', 'Di', 'eve', 'fay'];
const _tags = ['red', 'green', 'blue'];

List<Row> seedRows(int count, Random random) => [
      for (var i = 0; i < count; i++)
        Row(
          i,
          _names[random.nextInt(_names.length)],
          random.nextInt(5) == 0 ? null : random.nextInt(20),
          _tags[random.nextInt(_tags.length)],
        ),
    ];

/// The queries worth checking: each one exercises a different combination of
/// the stages the patch has to keep consistent.
List<GridQuery> queries() => [
      const GridQuery(),
      const GridQuery(sorts: [SortSpec('score')]),
      const GridQuery(
        sorts: [SortSpec('name'), SortSpec('score')],
      ),
      const GridQuery(
        sorts: [SortSpec('score', direction: SortDirection.descending)],
      ),
      const GridQuery(
        sorts: [SortSpec('score', nulls: NullsPosition.first)],
      ),
      const GridQuery(search: 'e'),
      const GridQuery(search: 'e', sorts: [SortSpec('name')]),
      const GridQuery(
        filter: FilterCondition(
          field: 'tag',
          operator: FilterOperator.equals,
          value: 'red',
        ),
      ),
      const GridQuery(
        filter: FilterCondition(
          field: 'score',
          operator: FilterOperator.greaterThan,
          value: 8,
        ),
        sorts: [SortSpec('score')],
      ),
      const GridQuery(
        filter: FilterCondition(
          field: 'score',
          operator: FilterOperator.greaterThan,
          value: 8,
        ),
        search: 'a',
        sorts: [SortSpec('name'), SortSpec('id')],
      ),
      const GridQuery(sorts: [SortSpec('name')], offset: 2, limit: 5),
    ];

/// Rows the same query returns from a source that has cached nothing.
List<Row> freshResult(List<Row> rows, GridQuery query) {
  final source = InMemoryDataSource<Row>(rows)
    ..columns = {for (final c in columns()) c.field: c};
  return source.fetchSync(query).rows;
}

void main() {
  batchPatchTests();

  group('an edit patched into a cached pipeline', () {
    test('gives the same rows as a source that cached nothing', () {
      final random = Random(20261116);
      for (final query in queries()) {
        final rows = seedRows(60, random);
        final source = InMemoryDataSource<Row>(rows)
          ..columns = {for (final c in columns()) c.field: c};
        // Warm every stage, which is the state a patch has to maintain.
        source.fetchSync(query);

        for (var edit = 0; edit < 120; edit++) {
          final at = random.nextInt(source.length);
          final old = source.rows[at];
          final replacement = Row(
            old.id,
            _names[random.nextInt(_names.length)],
            random.nextInt(5) == 0 ? null : random.nextInt(20),
            _tags[random.nextInt(_tags.length)],
          );
          source.replaceAt(at, replacement);

          final patched = source.fetchSync(query);
          final fresh = freshResult(source.rows, query);
          expect(
            [for (final row in patched.rows) row.id],
            [for (final row in fresh) row.id],
            reason: 'after edit $edit under $query',
          );
          expect(
            [for (final row in patched.rows) identityHashCode(row)],
            [for (final row in fresh) identityHashCode(row)],
            reason: 'the same instances, after edit $edit under $query',
          );
          expect(
            patched.matchedCount,
            freshCount(source.rows, query),
            reason: 'the count after edit $edit under $query',
          );
        }
      }
    });

    test('keeps the aggregates and the stats in step', () {
      final random = Random(7);
      final rows = seedRows(40, random);
      final source = InMemoryDataSource<Row>(rows)
        ..columns = {for (final c in columns()) c.field: c};
      const query = GridQuery(
        sorts: [SortSpec('score')],
        aggregations: [Aggregation('score', type: AggregateType.sum)],
      );
      source.fetchSync(query);

      for (var edit = 0; edit < 40; edit++) {
        final at = random.nextInt(source.length);
        final old = source.rows[at];
        source.replaceAt(
            at, Row(old.id, old.name, random.nextInt(50), old.tag));
        final patched = source.fetchSync(query);
        final fresh = InMemoryDataSource<Row>(source.rows)
          ..columns = {for (final c in columns()) c.field: c};
        expect(
          patched.aggregates.asMap,
          fresh.fetchSync(query).aggregates.asMap,
        );
        expect(source.statsFor('score').max, fresh.statsFor('score').max);
      }
    });

    test('a grouped query still recomputes, and stays right', () {
      final random = Random(11);
      final rows = seedRows(30, random);
      final source = InMemoryDataSource<Row>(rows)
        ..columns = {for (final c in columns()) c.field: c};
      const query = GridQuery(groups: [GroupSpec('tag')]);
      source.fetchSync(query);

      for (var edit = 0; edit < 30; edit++) {
        final at = random.nextInt(source.length);
        final old = source.rows[at];
        source.replaceAt(
          at,
          Row(old.id, old.name, old.score, _tags[random.nextInt(_tags.length)]),
        );
        final patched = source.fetchSync(query);
        final fresh = InMemoryDataSource<Row>(source.rows)
          ..columns = {for (final c in columns()) c.field: c};
        final freshGroups = fresh.fetchSync(query).groups;
        expect(
          [for (final g in patched.groups) '${g.label}:${g.rowCount}'],
          [for (final g in freshGroups) '${g.label}:${g.rowCount}'],
          reason: 'after edit $edit',
        );
      }
    });

    test('an edit through the grid moves the row it changed', () {
      final rows = [
        Row(1, 'ada', 1, 'red'),
        Row(2, 'bo', 2, 'red'),
        Row(3, 'cy', 3, 'red'),
      ];
      final source = InMemoryDataSource<Row>(rows);
      final grid = GridController<Row>(
        columns: [
          ...columns(),
          GridColumn<Row>(
            field: 'editable',
            type: ColumnType.number,
            value: (r) => r.score,
            setValue: (r, v) {
              r.score = v as num?;
              return null;
            },
          ),
        ],
        dataSource: source,
        sorts: const [SortSpec('score')],
        rowKey: (r) => r.id,
      );
      expect(
          [for (final r in grid.visibleRows) (r as DataGridRow<Row>).data.id],
          [1, 2, 3]);

      grid.beginEdit(const CellAddress(0, 'editable'));
      grid.updateEdit(99);
      grid.commitEdit();

      expect(
          [for (final r in grid.visibleRows) (r as DataGridRow<Row>).data.id],
          [2, 3, 1]);
      grid.dispose();
    });
  });
}

/// Rows a fresh source says matched.
int freshCount(List<Row> rows, GridQuery query) {
  final source = InMemoryDataSource<Row>(rows)
    ..columns = {for (final c in columns()) c.field: c};
  return source.fetchSync(query).matchedCount;
}

/// A batch write is patched row by row, and has to come out the same way.
void batchPatchTests() {
  group('a batch write', () {
    test('gives the same rows as a source that cached nothing', () async {
      final random = Random(99);
      final rows = seedRows(50, random);
      final source = InMemoryDataSource<Row>(rows)
        ..columns = {for (final c in columns()) c.field: c};
      const query = GridQuery(
        sorts: [SortSpec('score'), SortSpec('id')],
        search: 'a',
      );
      source.fetchSync(query);

      for (var batch = 0; batch < 20; batch++) {
        // Distinct rows: a batch that names one row twice is a caller error,
        // and the source says so rather than writing twice.
        final picked = <int>{};
        while (picked.length < 5) {
          picked.add(random.nextInt(source.length));
        }
        final writes = <RowUpdate<Row>>[
          for (final at in picked)
            () {
              final old = source.rows[at];
              return RowUpdate<Row>(
                old,
                Row(old.id, _names[random.nextInt(_names.length)],
                    random.nextInt(20), old.tag),
              );
            }(),
        ];
        await source.commitAll(writes);
        final patched = source.fetchSync(query);
        expect(
          [for (final row in patched.rows) row.id],
          [for (final row in freshResult(source.rows, query)) row.id],
          reason: 'after batch $batch',
        );
      }
    });
  });
}
