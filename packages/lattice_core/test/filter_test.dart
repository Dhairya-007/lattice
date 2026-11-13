import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> row({
    Object? name = 'Keyboard',
    Object? price = 80,
    Object? stock = 12,
  }) =>
      {'name': name, 'price': price, 'stock': stock};

  bool matches(FilterCondition condition, {Map<String, Object?>? on}) =>
      condition.matches(on ?? row());

  group('equality and text operators', () {
    test('equals and notEquals', () {
      expect(
        matches(const FilterCondition(
          field: 'name',
          operator: FilterOperator.equals,
          value: 'Keyboard',
        )),
        isTrue,
      );
      expect(
        matches(const FilterCondition(
          field: 'name',
          operator: FilterOperator.notEquals,
          value: 'Keyboard',
        )),
        isFalse,
      );
    });

    test('contains, startsWith and endsWith ignore case by default', () {
      expect(
        matches(const FilterCondition(
          field: 'name',
          operator: FilterOperator.contains,
          value: 'BOARD',
        )),
        isTrue,
      );
      expect(
        matches(const FilterCondition(
          field: 'name',
          operator: FilterOperator.startsWith,
          value: 'key',
        )),
        isTrue,
      );
      expect(
        matches(const FilterCondition(
          field: 'name',
          operator: FilterOperator.endsWith,
          value: 'ARD',
        )),
        isTrue,
      );
    });

    test('caseSensitive makes text comparisons exact', () {
      expect(
        matches(const FilterCondition(
          field: 'name',
          operator: FilterOperator.contains,
          value: 'BOARD',
          caseSensitive: true,
        )),
        isFalse,
      );
    });

    test('notContains is the negation of contains', () {
      expect(
        matches(const FilterCondition(
          field: 'name',
          operator: FilterOperator.notContains,
          value: 'mouse',
        )),
        isTrue,
      );
    });
  });

  group('ordering operators', () {
    test('greater and less, inclusive and exclusive', () {
      expect(
        matches(const FilterCondition(
          field: 'price',
          operator: FilterOperator.greaterThan,
          value: 50,
        )),
        isTrue,
      );
      expect(
        matches(const FilterCondition(
          field: 'price',
          operator: FilterOperator.greaterOrEqual,
          value: 80,
        )),
        isTrue,
      );
      expect(
        matches(const FilterCondition(
          field: 'price',
          operator: FilterOperator.lessThan,
          value: 80,
        )),
        isFalse,
      );
      expect(
        matches(const FilterCondition(
          field: 'price',
          operator: FilterOperator.lessOrEqual,
          value: 80,
        )),
        isTrue,
      );
    });

    test('between is inclusive at both ends', () {
      const condition = FilterCondition(
        field: 'price',
        operator: FilterOperator.between,
        value: 80,
        secondValue: 100,
      );
      expect(matches(condition), isTrue);
      expect(matches(condition, on: row(price: 100)), isTrue);
      expect(matches(condition, on: row(price: 101)), isFalse);
    });

    test('a null value never satisfies an ordering comparison', () {
      expect(
        matches(
          const FilterCondition(
            field: 'stock',
            operator: FilterOperator.greaterThan,
            value: 0,
          ),
          on: row(stock: null),
        ),
        isFalse,
      );
      expect(
        matches(
          const FilterCondition(
            field: 'stock',
            operator: FilterOperator.lessThan,
            value: 100,
          ),
          on: row(stock: null),
        ),
        isFalse,
      );
    });
  });

  group('set and null operators', () {
    test('isIn matches any member', () {
      const condition = FilterCondition(
        field: 'name',
        operator: FilterOperator.isIn,
        value: ['Mouse', 'Keyboard'],
      );
      expect(matches(condition), isTrue);
      expect(matches(condition, on: row(name: 'Monitor')), isFalse);
    });

    test('isNull, isNotNull, isEmpty and isNotEmpty', () {
      expect(
        matches(
          const FilterCondition(field: 'stock', operator: FilterOperator.isNull),
          on: row(stock: null),
        ),
        isTrue,
      );
      expect(
        matches(const FilterCondition(
          field: 'stock',
          operator: FilterOperator.isNotNull,
        )),
        isTrue,
      );
      expect(
        matches(
          const FilterCondition(
            field: 'name',
            operator: FilterOperator.isEmpty,
          ),
          on: row(name: ''),
        ),
        isTrue,
      );
      expect(
        matches(const FilterCondition(
          field: 'name',
          operator: FilterOperator.isNotEmpty,
        )),
        isTrue,
      );
    });
  });

  group('isEmpty', () {
    test('an unfilled condition is inert and matches everything', () {
      const condition = FilterCondition(
        field: 'name',
        operator: FilterOperator.contains,
      );
      expect(condition.isEmpty, isTrue);
      expect(matches(condition), isTrue);
    });

    test('an empty string counts as unfilled', () {
      expect(
        const FilterCondition(
          field: 'name',
          operator: FilterOperator.contains,
          value: '',
        ).isEmpty,
        isTrue,
      );
    });

    test('a half-filled between is unfilled', () {
      expect(
        const FilterCondition(
          field: 'price',
          operator: FilterOperator.between,
          value: 10,
        ).isEmpty,
        isTrue,
      );
    });

    test('null checks are never unfilled', () {
      expect(
        const FilterCondition(field: 'stock', operator: FilterOperator.isNull)
            .isEmpty,
        isFalse,
      );
    });

    test('an empty isIn list is unfilled', () {
      expect(
        const FilterCondition(
          field: 'name',
          operator: FilterOperator.isIn,
          value: <String>[],
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('FilterGroup', () {
    const expensive = FilterCondition(
      field: 'price',
      operator: FilterOperator.greaterThan,
      value: 50,
    );
    const named = FilterCondition(
      field: 'name',
      operator: FilterOperator.contains,
      value: 'mouse',
    );

    test('and requires every child', () {
      expect(const FilterGroup.and([expensive, named]).matches(row()), isFalse);
      expect(const FilterGroup.and([expensive]).matches(row()), isTrue);
    });

    test('or requires any child', () {
      expect(const FilterGroup.or([expensive, named]).matches(row()), isTrue);
      expect(const FilterGroup.or([named]).matches(row()), isFalse);
    });

    test('an empty group matches everything', () {
      expect(const FilterGroup.and([]).matches(row()), isTrue);
      expect(const FilterGroup.or([]).matches(row()), isTrue);
    });

    test('nests to arbitrary depth', () {
      const filter = FilterGroup.and([
        expensive,
        FilterGroup.or([
          named,
          FilterCondition(
            field: 'stock',
            operator: FilterOperator.greaterThan,
            value: 10,
          ),
        ]),
      ]);
      expect(filter.matches(row()), isTrue);
      expect(filter.matches(row(stock: 1)), isFalse);
    });

    test('reports every field it touches', () {
      expect(
        const FilterGroup.and([expensive, named]).fields,
        {'price', 'name'},
      );
    });
  });

  group('serialisation', () {
    test('a condition round-trips', () {
      const condition = FilterCondition(
        field: 'price',
        operator: FilterOperator.between,
        value: 10,
        secondValue: 20,
        caseSensitive: true,
      );
      final restored = Filter.fromJson(condition.toJson());
      expect(restored, condition);
    });

    test('a nested group round-trips and still matches the same rows', () {
      const filter = FilterGroup.or([
        FilterCondition(
          field: 'name',
          operator: FilterOperator.startsWith,
          value: 'Key',
        ),
        FilterGroup.and([
          FilterCondition(
            field: 'price',
            operator: FilterOperator.lessThan,
            value: 10,
          ),
        ]),
      ]);
      final restored = Filter.fromJson(filter.toJson());
      expect(restored.matches(row()), filter.matches(row()));
      expect(restored.fields, filter.fields);
    });

    test('an unknown operator is rejected rather than silently ignored', () {
      expect(
        () => Filter.fromJson({'field': 'name', 'op': 'sideways'}),
        throwsArgumentError,
      );
    });
  });
}
