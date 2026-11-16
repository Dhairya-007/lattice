/// Ordering primitives shared by sorting, grouping and range filters.
library;

/// Compares two arbitrary cell values in a total, null-safe order.
///
/// Nulls sort last. Values are ranked by type class first - booleans, then
/// numbers (including [BigInt]), then [DateTime], then strings, then anything
/// else - and only compared within a class. Ranking by class first is what
/// makes the order *total*: comparing across classes by their string forms
/// made the relation intransitive, so a column holding `9`, `10` and `'5'`
/// ordered differently depending on the input order and broke `List.sort`'s
/// contract.
///
/// Within the "anything else" class, two values of the same type that are
/// [Comparable] compare naturally, and everything else compares by its string
/// form so that ordering is at least stable between rebuilds.
int compareValues(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  // The fast path: the overwhelmingly common case is two values of the same
  // primitive type, and it must not pay for the type ranking below.
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is DateTime && b is DateTime) return a.compareTo(b);

  final rankA = _typeRank(a);
  final rankB = _typeRank(b);
  if (rankA != rankB) return rankA < rankB ? -1 : 1;

  switch (rankA) {
    case _rankBool:
      final ba = a as bool;
      final bb = b as bool;
      if (ba == bb) return 0;
      return ba ? 1 : -1;
    case _rankNumber:
      return _compareNumeric(a, b);
    case _rankDate:
      return (a as DateTime).compareTo(b as DateTime);
    case _rankString:
      return (a as String).compareTo(b as String);
    default:
      if (a is Comparable &&
          b is Comparable &&
          a.runtimeType == b.runtimeType) {
        return a.compareTo(b);
      }
      return '$a'.compareTo('$b');
  }
}

const int _rankBool = 0;
const int _rankNumber = 1;
const int _rankDate = 2;
const int _rankString = 3;
const int _rankOther = 4;

int _typeRank(Object value) {
  if (value is bool) return _rankBool;
  if (value is num || value is BigInt) return _rankNumber;
  if (value is DateTime) return _rankDate;
  if (value is String) return _rankString;
  return _rankOther;
}

/// Compares two numeric values, which may mix [num] and [BigInt].
///
/// A [BigInt] used to be compared by its string form, so `BigInt.from(10)`
/// sorted below `9`. Mixed comparisons go through [BigInt] when the other
/// side is an [int] - exact at any magnitude - and through [double] when it
/// is not, which is the best a binary float can say about the pair.
int _compareNumeric(Object a, Object b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is BigInt && b is BigInt) return a.compareTo(b);
  if (a is BigInt && b is int) return a.compareTo(BigInt.from(b));
  if (a is int && b is BigInt) return BigInt.from(a).compareTo(b);
  // One side is a BigInt and the other a double.
  final da = a is BigInt ? a.toDouble() : (a as num).toDouble();
  final db = b is BigInt ? b.toDouble() : (b as num).toDouble();
  return da.compareTo(db);
}

/// Case- and accent-insensitive variant of [compareValues] for text columns.
///
/// Folded equality is broken by the exact comparison, so the order stays
/// total and `'Apple'` and `'apple'` keep a stable relative position. Filters
/// must not use this - an equality test wants [compareValuesFolded], where
/// two values that differ only in case or accent compare equal.
int compareValuesCaseInsensitive(Object? a, Object? b) {
  if (a is String && b is String) {
    final byFold = foldText(a).compareTo(foldText(b));
    // Fall back to the exact comparison so the order stays total.
    return byFold != 0 ? byFold : a.compareTo(b);
  }
  return compareValues(a, b);
}

/// Compares values with case and accents folded away and *no* tiebreak, so
/// that `'Apple'`, `'apple'` and `'ápple'` all compare equal.
///
/// This is the comparison a case-insensitive filter needs. The tiebreaking
/// variant, [compareValuesCaseInsensitive], is correct for a sort order and
/// wrong here: it reports `'Apple' == 'apple'` as a difference, which made a
/// case-insensitive `equals` filter case-sensitive in practice, and made
/// `>=` exclude a value it had just called equal.
int compareValuesFolded(Object? a, Object? b) {
  if (a is String && b is String) return foldText(a).compareTo(foldText(b));
  return compareValues(a, b);
}

/// Whether [a] and [b] are the same value, ignoring case and accents in text.
bool valuesEqualFolded(Object? a, Object? b) => compareValuesFolded(a, b) == 0;

/// Lowercases [text] and strips the diacritics the Latin alphabet writes with,
/// so that `Crème` folds to `creme` and sorts next to `cream`.
///
/// Used by case-insensitive sorting, filtering and search. It covers Latin-1
/// Supplement and Latin Extended-A, which is what European data arrives in;
/// it is deliberately not a full Unicode collation, which would need tables
/// this package will not carry.
String foldText(String text) {
  final lower = text.toLowerCase();
  // Overwhelmingly the common case is plain ASCII, which needs no folding
  // and must not pay for a scan that rewrites anything.
  var needsFolding = false;
  for (var i = 0; i < lower.length; i++) {
    if (lower.codeUnitAt(i) > 0x7F) {
      needsFolding = true;
      break;
    }
  }
  if (!needsFolding) return lower;

  final out = StringBuffer();
  for (var i = 0; i < lower.length; i++) {
    final unit = lower.codeUnitAt(i);
    if (unit <= 0x7F) {
      out.writeCharCode(unit);
      continue;
    }
    final folded = _diacritics[unit];
    if (folded == null) {
      out.writeCharCode(unit);
    } else {
      out.write(folded);
    }
  }
  return out.toString();
}

/// Lowercase accented code unit -> its unaccented form.
///
/// Only lowercase keys appear, because [foldText] lowercases first. A few
/// entries expand to two letters (`æ` -> `ae`), which is why the values are
/// strings.
const Map<int, String> _diacritics = {
  0xE0: 'a',
  0xE1: 'a',
  0xE2: 'a',
  0xE3: 'a',
  0xE4: 'a',
  0xE5: 'a',
  0xE6: 'ae',
  0xE7: 'c',
  0xE8: 'e',
  0xE9: 'e',
  0xEA: 'e',
  0xEB: 'e',
  0xEC: 'i',
  0xED: 'i',
  0xEE: 'i',
  0xEF: 'i',
  0xF0: 'd',
  0xF1: 'n',
  0xF2: 'o',
  0xF3: 'o',
  0xF4: 'o',
  0xF5: 'o',
  0xF6: 'o',
  0xF8: 'o',
  0xF9: 'u',
  0xFA: 'u',
  0xFB: 'u',
  0xFC: 'u',
  0xFD: 'y',
  0xFF: 'y',
  0xFE: 'th',
  0xDF: 'ss',
  0x101: 'a',
  0x103: 'a',
  0x105: 'a',
  0x107: 'c',
  0x109: 'c',
  0x10B: 'c',
  0x10D: 'c',
  0x10F: 'd',
  0x111: 'd',
  0x113: 'e',
  0x115: 'e',
  0x117: 'e',
  0x119: 'e',
  0x11B: 'e',
  0x11D: 'g',
  0x11F: 'g',
  0x121: 'g',
  0x123: 'g',
  0x125: 'h',
  0x127: 'h',
  0x129: 'i',
  0x12B: 'i',
  0x12D: 'i',
  0x12F: 'i',
  0x131: 'i',
  0x135: 'j',
  0x137: 'k',
  0x13A: 'l',
  0x13C: 'l',
  0x13E: 'l',
  0x140: 'l',
  0x142: 'l',
  0x144: 'n',
  0x146: 'n',
  0x148: 'n',
  0x14D: 'o',
  0x14F: 'o',
  0x151: 'o',
  0x153: 'oe',
  0x155: 'r',
  0x157: 'r',
  0x159: 'r',
  0x15B: 's',
  0x15D: 's',
  0x15F: 's',
  0x161: 's',
  0x163: 't',
  0x165: 't',
  0x167: 't',
  0x169: 'u',
  0x16B: 'u',
  0x16D: 'u',
  0x16F: 'u',
  0x171: 'u',
  0x173: 'u',
  0x175: 'w',
  0x177: 'y',
  0x17A: 'z',
  0x17C: 'z',
  0x17E: 'z',
};

/// Compares values the way a human reads embedded numbers, so that
/// `item2` sorts before `item10`.
///
/// Digit runs compare as numbers of any length - `a99999999999999999999` and
/// `a100000000000000000000` order correctly, though neither fits an `int` -
/// and the text between them compares with case and accents folded, broken by
/// the exact comparison so the order stays total.
///
/// The comparison allocates nothing and builds no [RegExp]: it used to do both
/// on every call, which made it 45x slower than the default sort over 50k
/// rows. A column that sorts naturally over a large grid should still prefer
/// [GridColumn.sortKey], which pays per row instead of per comparison.
int compareValuesNatural(Object? a, Object? b) {
  if (a is! String || b is! String) return compareValues(a, b);
  final byChunk = _compareNaturalFolded(a, b);
  // Equal but for case or accent: break the tie exactly, so the order is
  // total and two spellings keep a stable relative position.
  return byChunk != 0 ? byChunk : a.compareTo(b);
}

int _compareNaturalFolded(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    final aDigit = _isDigit(ca);
    final bDigit = _isDigit(cb);
    if (aDigit && bDigit) {
      // Skip leading zeros: '007' and '7' are the same number, and the
      // length comparison below needs the significant digits only.
      var si = i;
      while (si < a.length && a.codeUnitAt(si) == _zero) {
        si++;
      }
      var sj = j;
      while (sj < b.length && b.codeUnitAt(sj) == _zero) {
        sj++;
      }
      var ei = si;
      while (ei < a.length && _isDigit(a.codeUnitAt(ei))) {
        ei++;
      }
      var ej = sj;
      while (ej < b.length && _isDigit(b.codeUnitAt(ej))) {
        ej++;
      }
      final lenA = ei - si;
      final lenB = ej - sj;
      // More significant digits means a larger number, whatever the digits
      // are, which is what makes this exact beyond int64.
      if (lenA != lenB) return lenA < lenB ? -1 : 1;
      for (var k = 0; k < lenA; k++) {
        final da = a.codeUnitAt(si + k);
        final db = b.codeUnitAt(sj + k);
        if (da != db) return da < db ? -1 : 1;
      }
      i = ei;
      j = ej;
      continue;
    }
    if (aDigit != bDigit) {
      // A digit run and a letter at the same position: order by the
      // characters, so 'a1' and 'ab' stay in a defined order.
      return ca < cb ? -1 : 1;
    }
    final fa = _foldUnit(ca);
    final fb = _foldUnit(cb);
    if (fa != fb) return fa < fb ? -1 : 1;
    i++;
    j++;
  }
  final restA = a.length - i;
  final restB = b.length - j;
  if (restA == restB) return 0;
  return restA < restB ? -1 : 1;
}

const int _zero = 0x30;
const int _nine = 0x39;

bool _isDigit(int unit) => unit >= _zero && unit <= _nine;

/// Folds one code unit for the natural comparison: ASCII upper case to lower,
/// and a single-letter diacritic to its base letter.
///
/// Multi-letter expansions such as `æ` cannot be represented by one unit, so
/// they fall through unchanged here; [compareValuesNatural]'s exact tiebreak
/// keeps the order total either way.
int _foldUnit(int unit) {
  if (unit >= 0x41 && unit <= 0x5A) return unit + 0x20;
  if (unit <= 0x7F) return unit;
  final folded = _diacritics[unit] ?? _diacritics[_lowerUnit(unit)];
  if (folded != null && folded.length == 1) return folded.codeUnitAt(0);
  return unit;
}

int _lowerUnit(int unit) {
  final lower = String.fromCharCode(unit).toLowerCase();
  return lower.length == 1 ? lower.codeUnitAt(0) : unit;
}

/// A key that sorts like [compareValuesNatural] under a plain string
/// comparison, for use as a [GridColumn.sortKey].
///
/// Each digit run is rewritten as its length (base 36, itself length-prefixed)
/// followed by its significant digits, so that a longer number always sorts
/// above a shorter one. Computing this once per row turns a natural sort from
/// a per-comparison cost into a per-row one.
String naturalSortKey(Object? value) {
  if (value is! String) return value == null ? '' : foldText('$value');
  final text = foldText(value);
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final unit = text.codeUnitAt(i);
    if (!_isDigit(unit)) {
      out.writeCharCode(unit);
      i++;
      continue;
    }
    var start = i;
    while (start < text.length && text.codeUnitAt(start) == _zero) {
      start++;
    }
    var end = start;
    while (end < text.length && _isDigit(text.codeUnitAt(end))) {
      end++;
    }
    final digits = text.substring(start, end);
    final length = digits.length.toRadixString(36);
    // The length of the length, so that keys with very long digit runs still
    // compare in the right order.
    out.write('\u0000');
    out.write(length.length.toRadixString(36));
    out.write(length);
    out.write(digits);
    i = end == i ? i + 1 : end;
  }
  return out.toString();
}
