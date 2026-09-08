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
    final cents = parseScaled(input, decimals: 2);
    return cents == null ? null : Money(cents);
  }

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
  String format({String currencyCode = settlementCurrency, String locale = 'es'}) {
    final numbers = NumberFormat.decimalPattern(locale);

    final sign = cents < 0 ? '-' : '';
    final wholePart = numbers.format(cents.abs() ~/ 100);
    final centsPart = (cents.abs() % 100).toString().padLeft(2, '0');

    return '$sign${_symbolFor(currencyCode)} $wholePart'
        '${numbers.symbols.DECIMAL_SEP}$centsPart';
  }

  /// The same amount without a currency symbol, for text fields.
  String get asPlainText => (cents / 100).toStringAsFixed(2);

  /// Falls back to the code itself for anything unlisted, so a currency the
  /// server starts accepting before this app knows about it still renders as
  /// "PYG 1.000,00" instead of disappearing.
  static String _symbolFor(String currencyCode) =>
      currencies[currencyCode]?.symbol ?? currencyCode;
}

/// The unit every balance, settlement and debt in this app is expressed in.
///
/// A group has no currency of its own. Its expenses each carry the money they
/// were actually paid in, and every one of them is converted into this on the
/// way to the server — once, at the rate agreed that day.
const settlementCurrency = 'USDT';

/// What an expense can have been paid in.
///
/// One map, so adding a currency is a single edit. The alternative — a symbol
/// switch here and a hardcoded list of codes in the dropdown — is how you end
/// up able to pick a currency the formatter does not recognise. It also has
/// to agree with SPENDABLE_CURRENCIES on the server, which is the list that
/// actually decides: anything else comes back a 400.
const currencies = <String, ({String symbol, String name})>{
  'USDT': (symbol: 'USDT', name: 'Dólar cripto'),
  'BOB': (symbol: 'Bs', name: 'Boliviano'),
  'USD': (symbol: r'US$', name: 'Dólar estadounidense'),
};

/// How many millionths of a currency buy one USDT.
///
/// A rate is a decimal by nature — 6,96 bolivianos to the dollar — and a
/// decimal is exactly what this file exists to keep away from money. So it is
/// scaled by a million and carried as an int, the same way the server stores
/// it: 6,96 is 6960000. Six digits is what USDT itself uses on chain, and it
/// leaves room for a rate like 6,957382 that is not a rounding of anything.
extension type const Rate(int micros) implements Object {
  static const int parMicros = 1000000;

  /// One USDT is one USDT: the only rate that is not a matter of opinion.
  static const Rate par = Rate(parMicros);

  bool get isPar => micros == parMicros;
  bool get isUsable => micros > 0;

  /// Returns null instead of throwing: a half-typed rate is the normal state
  /// of a text field, not an error.
  static Rate? tryParse(String input) {
    final micros = parseScaled(input, decimals: 6);
    return micros == null || micros <= 0 ? null : Rate(micros);
  }

  /// "6,96" — trailing zeros trimmed, because 6,960000 reads like precision
  /// nobody claimed.
  String format({String locale = 'es'}) {
    final whole = micros ~/ parMicros;
    final fraction =
        (micros % parMicros).toString().padLeft(6, '0').replaceAll(RegExp(r'0+$'), '');
    final separator = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;

    return fraction.isEmpty ? '$whole' : '$whole$separator$fraction';
  }

  /// The same rate for a text field: always a dot, never grouped.
  String get asPlainText {
    final fraction =
        (micros % parMicros).toString().padLeft(6, '0').replaceAll(RegExp(r'0+$'), '');
    return fraction.isEmpty
        ? '${micros ~/ parMicros}'
        : '${micros ~/ parMicros}.$fraction';
  }
}

/// Reads a typed decimal into an integer scaled by 10^[decimals].
///
/// "1234,56", "1234.56", "1.234,56" and "1234" all work: whichever separator
/// comes last is the decimal one and the other is grouping, which makes
/// "1.234,56" and "1,234.56" both unambiguous. Money uses two decimals and a
/// rate uses six, and they share this because a second hand-rolled decimal
/// parser is a second place for a decimal point to move on its own.
///
/// Returns null for anything it cannot read, including more decimals than
/// asked for — silently dropping the digits somebody typed is worse than
/// telling them the field is not valid yet.
int? parseScaled(String input, {required int decimals}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final lastComma = trimmed.lastIndexOf(',');
  final lastDot = trimmed.lastIndexOf('.');
  final decimalMark = lastComma > lastDot ? ',' : '.';

  final digitsOnly = trimmed
      .split('')
      .where((character) => _isDigit(character) || character == decimalMark)
      .join();

  // "abc" survives the filter as an empty string, and an empty string would
  // otherwise parse as zero. A field full of letters is not worth 0,00.
  if (!digitsOnly.split('').any(_isDigit)) return null;

  final parts = digitsOnly.split(decimalMark);
  if (parts.length > 2) return null;

  final whole = parts[0].isEmpty ? '0' : parts[0];
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals) return null;

  final wholeValue = int.tryParse(whole);
  final fractionValue = int.tryParse(fraction.padRight(decimals, '0'));
  if (wholeValue == null || fractionValue == null) return null;

  var scale = 1;
  for (var i = 0; i < decimals; i++) {
    scale *= 10;
  }

  return wholeValue * scale + fractionValue;
}

bool _isDigit(String character) =>
    character.codeUnitAt(0) >= 0x30 && character.codeUnitAt(0) <= 0x39;
