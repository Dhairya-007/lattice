import 'package:lattice_core/lattice_core.dart';

/// Mutable row model, so editing tests can exercise in-place writes.
class Product {
  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.stock,
    this.active = true,
  });

  final int id;
  String name;
  String category;
  num price;
  int? stock;
  bool active;

  @override
  String toString() => 'Product($id, $name)';
}

List<GridColumn<Product>> productColumns() => [
      GridColumn<Product>(
        field: 'name',
        value: (p) => p.name,
        setValue: (p, v) {
          p.name = (v ?? '') as String;
          return null;
        },
        validator: requiredValue(),
      ),
      GridColumn<Product>(field: 'category', value: (p) => p.category),
      GridColumn<Product>(
        field: 'price',
        type: ColumnType.number,
        value: (p) => p.price,
        format: (v) => v == null ? '' : '${(v as num).toStringAsFixed(2)} USD',
        setValue: (p, v) {
          p.price = (v ?? 0) as num;
          return null;
        },
        validator: numberRange(min: 0),
      ),
      GridColumn<Product>(
        field: 'stock',
        type: ColumnType.number,
        value: (p) => p.stock,
      ),
      GridColumn<Product>(
        field: 'active',
        type: ColumnType.boolean,
        value: (p) => p.active,
      ),
    ];

List<Product> sampleProducts() => [
      Product(id: 1, name: 'Keyboard', category: 'Input', price: 80, stock: 12),
      Product(id: 2, name: 'Mouse', category: 'Input', price: 25, stock: 40),
      Product(
          id: 3, name: 'Monitor', category: 'Display', price: 320, stock: 5),
      Product(id: 4, name: 'Laptop', category: 'Compute', price: 1450),
      Product(
        id: 5,
        name: 'Dock',
        category: 'Compute',
        price: 180,
        stock: 7,
        active: false,
      ),
      Product(id: 6, name: 'Webcam', category: 'Input', price: 60, stock: 0),
    ];

Map<String, GridColumn<Product>> productColumnMap() =>
    {for (final c in productColumns()) c.field: c};

/// Builds a controller over the sample data.
GridController<Product> productGrid({
  List<SortSpec> sorts = const [],
  List<GroupSpec> groups = const [],
  List<Aggregation> aggregations = const [],
  int? pageSize,
  SelectionMode selectionMode = SelectionMode.multiRow,
  List<Product>? rows,
}) {
  return GridController<Product>(
    columns: productColumns(),
    dataSource: InMemoryDataSource<Product>(rows ?? sampleProducts()),
    sorts: sorts,
    groups: groups,
    aggregations: aggregations,
    pageSize: pageSize,
    selectionMode: selectionMode,
  );
}

/// Row labels in display order: product names, and group labels for headers.
List<String> labelsOf(GridController<Product> grid) => [
      for (final row in grid.visibleRows)
        if (row is DataGridRow<Product>)
          row.data.name
        else
          (row as GroupGridRow<Product>).label,
    ];
