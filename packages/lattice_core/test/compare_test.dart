// The comparison primitives, which every other stage orders by.
//
// A grid's sort has to be a total order: `List.sort` may do anything at all
// with a comparator that contradicts itself, so an intransitive comparison is
// not a cosmetic bug but a source of results that differ between runs.
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

void main() {
  group('compareValues', () {
    test('orders by type class, so mixed values stay transitive', () {
      // 9 < 10 numerically, 10 < '5' as text, '5' < 9 as text: a cycle, and
      // a cycle is what made a mixed column sort differently each run.
      expect(compareValues(9, 10), lessThan(0));
      expect(compareValues(10, '5'), lessThan(0));
      expect(compareValues('5', 9), greaterThan(0));

      final values = <Object?>[10, '5', 9, true, DateTime(2024)];
      for (final a in values) {
        for (final b in values) {
          for (final c in values) {
            if (compareValues(a, b) < 0 && compareValues(b, c) < 0) {
              expect(
                compareValues(a, c),
                lessThan(0),
                reason: 'a<b and b<c must mean a<c for $a, $b, $c',
              );
            }
          }
        }
      }
    });

    test('compares a BigInt as a number, not as text', () {
      expect(compareValues(BigInt.from(10), 9), greaterThan(0));
      expect(compareValues(BigInt.from(9), 10), lessThan(0));
      expect(compareValues(BigInt.from(2), BigInt.from(10)), lessThan(0));
      expect(
        compareValues(BigInt.parse('99999999999999999999'), 1.5),
        greaterThan(0),
      );
    });

    test('places nulls last whichever side they are on', () {
      expect(compareValues(null, 1), greaterThan(0));
      expect(compareValues(1, null), lessThan(0));
      expect(compareValues(null, null), 0);
    });
  });

  group('folding', () {
    test('folds case and the diacritics Latin text is written with', () {
      expect(foldText('Crème Brûlée'), 'creme brulee');
      expect(foldText('ÉCOLE'), 'ecole');
      expect(foldText('straße'), 'strasse');
      expect(foldText('plain ascii'), 'plain ascii');
    });

    test('sorts an accented word next to its unaccented spelling', () {
      // Code-unit order puts every accent after `z`, so `école` sorted below
      // `zebra` even though a reader looks for it under E.
      expect(compareValuesCaseInsensitive('école', 'zebra'), lessThan(0));
      expect(compareValuesCaseInsensitive('Apple', 'apricot'), lessThan(0));
    });

    test('breaks a folded tie exactly, so the order stays total', () {
      expect(compareValuesCaseInsensitive('Apple', 'apple'), isNot(0));
      expect(
        compareValuesCaseInsensitive('apple', 'Apple'),
        -compareValuesCaseInsensitive('Apple', 'apple'),
      );
    });

    test('compareValuesFolded calls two spellings equal, with no tiebreak', () {
      // This is the comparison a case-insensitive filter needs: the
      // tiebreaking variant reports a difference, which is what made
      // `equals: 'apple'` miss `'Apple'`.
      expect(compareValuesFolded('Apple', 'apple'), 0);
      expect(compareValuesFolded('ápple', 'APPLE'), 0);
      expect(valuesEqualFolded('Apple', 'apple'), isTrue);
      expect(valuesEqualFolded('Apple', 'apricot'), isFalse);
      expect(compareValuesFolded(5, 5), 0);
    });
  });

  group('compareValuesNatural', () {
    test('reads embedded numbers the way a human does', () {
      final codes = ['item10', 'item2', 'item1']..sort(compareValuesNatural);
      expect(codes, ['item1', 'item2', 'item10']);
    });

    test('orders digit runs that do not fit an int', () {
      // Both of these overflow int64, so parsing them gave the same value and
      // the comparison fell back to text.
      expect(
        compareValuesNatural(
          'a99999999999999999999',
          'a100000000000000000000',
        ),
        lessThan(0),
      );
      expect(
        compareValuesNatural('x000000000000000000007', 'x7'),
        lessThan(0), // equal numbers; the exact tiebreak decides
      );
    });

    test('ignores leading zeros when comparing numbers', () {
      final codes = ['v007', 'v10', 'v2']..sort(compareValuesNatural);
      expect(codes, ['v2', 'v007', 'v10']);
    });

    test('folds case in the text between numbers', () {
      expect(compareValuesNatural('Item2', 'item10'), lessThan(0));
    });

    test('naturalSortKey orders like the comparison it replaces', () {
      final codes = [
        'item10',
        'item2',
        'Item1',
        'item99999999999999999999',
        'item100000000000000000000',
      ];
      final byComparison = [...codes]..sort(compareValuesNatural);
      final byKey = [...codes]
        ..sort((a, b) => naturalSortKey(a).compareTo(naturalSortKey(b)));
      expect(byKey, byComparison);
    });
  });
}
