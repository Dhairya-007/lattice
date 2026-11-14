// Runs the whole engine without any UI: dart example/lattice_core_example.dart
import 'package:lattice_core/lattice_core.dart';

class Employee {
  Employee(this.name, this.department, this.salary, this.startedOn);

  final String name;
  final String department;
  num salary;
  final DateTime startedOn;
}

final employees = [
  Employee('Asha', 'Engineering', 142000, DateTime(2021, 3, 1)),
  Employee('Bruno', 'Engineering', 128000, DateTime(2022, 7, 14)),
  Employee('Chen', 'Design', 96000, DateTime(2020, 1, 20)),
  Employee('Dalia', 'Design', 104000, DateTime(2023, 5, 2)),
  Employee('Emre', 'Sales', 88000, DateTime(2019, 11, 9)),
  Employee('Farah', 'Sales', 115000, DateTime(2024, 2, 17)),
  Employee('Gita', 'Engineering', 156000, DateTime(2018, 6, 30)),
];

void main() {
  final controller = GridController<Employee>(
    columns: [
      GridColumn<Employee>(
        field: 'name',
        value: (e) => e.name,
        pin: ColumnPin.start,
      ),
      GridColumn<Employee>(field: 'department', value: (e) => e.department),
      GridColumn<Employee>(
        field: 'salary',
        type: ColumnType.number,
        value: (e) => e.salary,
        format: (v) => v == null ? '' : '\$${(v as num) ~/ 1000}k',
        setValue: (e, v) {
          e.salary = v! as num;
          return null;
        },
        validator: numberRange(min: 0),
      ),
      GridColumn<Employee>(
        field: 'startedOn',
        title: 'Started',
        type: ColumnType.date,
        value: (e) => e.startedOn,
        format: (v) => v == null ? '' : (v as DateTime).year.toString(),
      ),
    ],
    dataSource: InMemoryDataSource<Employee>(employees),
    aggregations: const [
      Aggregation.sum('salary'),
      Aggregation.average('salary'),
    ],
  );

  print('-- sorted by salary, highest first');
  controller.setSorts(
    const [SortSpec('salary', direction: SortDirection.descending)],
  );
  _dump(controller);

  print('\n-- searching for "sales"');
  controller.setSearch('sales');
  _dump(controller);
  print('matched ${controller.matchedCount} of ${controller.totalCount}');

  print('\n-- grouped by department, with aggregates');
  controller.setSearch('');
  controller.groupBy('department');
  _dump(controller);
  print('payroll total: ${controller.aggregates['salary.sum']}');

  print('\n-- filtering to salaries above 100k');
  controller.clearGroups();
  controller.setColumnFilter(
    'salary',
    const FilterCondition(
      field: 'salary',
      operator: FilterOperator.greaterThan,
      value: 100000,
    ),
  );
  _dump(controller);

  print('\n-- editing a cell, which re-sorts the row into place');
  controller.clearFilters();
  controller.setSorts(const [SortSpec('salary')]);
  final cell = CellAddress(0, 'salary');
  controller.beginEdit(cell);
  controller.updateEdit(200000);
  final result = controller.commitEdit();
  print('committed: ${result.isCommitted}');
  _dump(controller);

  print('\n-- rejecting an invalid edit');
  controller.beginEdit(CellAddress(0, 'salary'));
  controller.updateEdit(-1);
  print('error: ${controller.commitEdit().error}');
  controller.cancelEdit();

  print('\n-- CSV export of the current view');
  print(controller.exportCsv().trimRight());
}

void _dump(GridController<Employee> controller) {
  final columns = controller.visibleColumns;
  for (final row in controller.visibleRows) {
    switch (row) {
      case GroupGridRow<Employee>(:final label, :final rowCount, :final depth):
        print('${'  ' * depth}$label ($rowCount)');
      case DataGridRow<Employee>(:final data, :final depth):
        final cells =
            columns.map((c) => c.formattedValue(data).padRight(12)).join();
        print('${'  ' * depth}$cells');
      case DetailGridRow<Employee>(:final data, :final depth):
        // An open detail panel. What goes in it is the adapter's business;
        // a console dump just says it is there.
        print('${'  ' * (depth + 1)}... details for ${data.name}');
    }
  }
}
