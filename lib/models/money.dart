import 'package:intl/intl.dart';

/// An amount of money, as an integer number of cents.
///
/// This is an extension type, so at runtime it IS an int — no allocation, no
/// wrapper object. What it buys is a compiler that refuses to let a double
/// anywhere near an amount.
///
/// The reason is not style. 0.1 + 0.2 is 0.30000000000000004 in every
/// language with binary floating point, Dart included. Split a bill three
/// ways in doubles and the cents stop adding up to the total; do it a
/// thousand times and somebody is quietly short. The backend already refuses
/// to store anything but integers, and the app has no business being sloppier
/// than the database.
extension type const Money(int cents) implements Object {
  static const Money zero = Money(0);

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator -() => Money(-cents);

  bool operator >(Money other) => cents > other.cents;
  bool operator <(Money other) => cents < other.cents;

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;
  bool get isNegative => cents < 0;

  Money get absolute => Money(cents.abs());

  /// Reads what somebody typed: "1234,56", "1234.56", "1.234,56", "1234".
  ///
  /// Returns null instead of throwing, because a half-typed amount is the
  /// normal state of a text field, not an error.
  static Money? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Whichever separator comes last is the decimal one; the other is
    // grouping. "1.234,56" and "1,234.56" are both unambiguous this way.
    final lastComma = trimmed.lastIndexOf(',');
    final lastDot = trimmed.lastIndexOf('.');
    final decimalMark = lastComma > lastDot ? ',' : '.';

    final digitsOnly = trimmed
        .split('')
        .where((character) => _isDigit(character) || character == decimalMark)
        .join();

    // "abc" survives the filter as an empty string, and an empty string would
    // otherwise parse as zero. A field full of letters is not worth $0.00.
    if (!digitsOnly.split('').any(_isDigit)) return null;

    final parts = digitsOnly.split(decimalMark);
    if (parts.length > 2) return null;

    final whole = parts[0].isEmpty ? '0' : parts[0];
    final fraction = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
    if (fraction.length > 2) return null;

    final wholeCents = int.tryParse(whole);
    final fractionCents = int.tryParse(fraction);
    if (wholeCents == null || fractionCents == null) return null;

    return Money(wholeCents * 100 + fractionCents);
  }

  static bool _isDigit(String character) =>
      character.codeUnitAt(0) >= 0x30 && character.codeUnitAt(0) <= 0x39;

  /// "$ 1.234,56", and "-$ 1.234,56" when somebody is in the red.
  ///
  /// NumberFormat.currency is not used here for two reasons. It puts the
  /// symbol where the locale says, which for Spanish means the end — wrong
  /// for Argentina, Bolivia and Uruguay, where the sign goes first. And it
  /// takes a double, which would mean converting to floating point after all
  /// this trouble. The whole part and the cents are formatted as the integers
  /// they are; only the thousands separator and the decimal mark come from
  /// intl.
  ///
  /// The locale decides the separators, the currency decides the symbol, and
  /// they are deliberately two arguments. A Bolivian looking at a group in
  /// pesos should read Bolivian separators and an Argentine symbol; tying one
  /// to the other would make that impossible.
  ///
  /// `es` is the default rather than `es_419`: plain Spanish groups as
  /// 1.234,56, while the "Latin America" locale groups as 1,234.56. They are
  /// not interchangeable, and picking the wrong one silently moves a decimal
  /// point.
  String format({String currencyCode = 'ARS', String locale = 'es'}) {
    final numbers = NumberFormat.decimalPattern(locale);

    final sign = cents < 0 ? '-' : '';
    final wholePart = numbers.format(cents.abs() ~/ 100);
    final centsPart = (cents.abs() % 100).toString().padLeft(2, '0');

    return '$sign${_symbolFor(currencyCode)} $wholePart'
        '${numbers.symbols.DECIMAL_SEP}$centsPart';
  }

  /// The same amount without a currency symbol, for text fields.
  String get asPlainText => (cents / 100).toStringAsFixed(2);

  /// Falls back to the code itself for anything unlisted. The backend accepts
  /// any ISO-4217 code, so a group can exist in a currency this app has never
  /// heard of — showing "PYG 1.000,00" is worth more than showing nothing.
  static String _symbolFor(String currencyCode) =>
      currencies[currencyCode]?.symbol ?? currencyCode;
}

/// The currencies a group can be created in.
///
/// One map, so adding a currency is a single edit. The alternative — a symbol
/// switch here and a hardcoded list of codes in the dropdown — is how you end
/// up able to pick a currency the formatter does not recognise.
const currencies = <String, ({String symbol, String name})>{
  'ARS': (symbol: r'$', name: 'Peso argentino'),
  'BOB': (symbol: 'Bs', name: 'Boliviano'),
  'UYU': (symbol: r'$U', name: 'Peso uruguayo'),
  'BRL': (symbol: r'R$', name: 'Real brasileño'),
  'USD': (symbol: r'US$', name: 'Dólar estadounidense'),
  'EUR': (symbol: '€', name: 'Euro'),
};
