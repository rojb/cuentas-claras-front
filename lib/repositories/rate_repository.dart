import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/money.dart';

/// A live exchange rate the server fetched from Binance.
class RemoteRate {
  const RemoteRate({
    required this.rate,
    required this.fetchedAt,
    required this.stale,
  });

  final Rate rate;
  final DateTime fetchedAt;

  /// The server could not reach Binance and handed back the last value it
  /// had. Still usable, worth telling the person.
  final bool stale;
}

/// What one USDT is worth right now.
///
/// This is the one thing about money the app cannot work out on its own:
/// every balance, split and settlement is integer arithmetic, but the rate
/// only exists because a market says so and it moves every few minutes.
///
/// It does NOT change how the ledger works. An expense still carries its own
/// rate, frozen the day it was spent; this only fills the field the user
/// would otherwise type it into.
class RateRepository {
  const RateRepository(this._api);

  final ApiClient _api;

  /// The live rate for [currencyCode], or null when the server has none to
  /// give — no connection, or Binance unreachable with nothing cached.
  ///
  /// Null instead of an exception on purpose. Every kind of failure here has
  /// the same answer: show an empty field and let the two people type the
  /// rate themselves, exactly as they did before this endpoint existed.
  /// Throwing would only make each form re-implement that same fallback.
  Future<RemoteRate?> currentRate(String currencyCode) async {
    // One USDT is one USDT. No point in a round trip to be told so.
    if (currencyCode == settlementCurrency) {
      return RemoteRate(rate: Rate.par, fetchedAt: DateTime.now(), stale: false);
    }

    try {
      final response =
          await _api.get('/rates/$currencyCode') as Map<String, dynamic>;

      return RemoteRate(
        rate: Rate(response['rateMicros'] as int),
        fetchedAt: DateTime.parse(response['fetchedAt'] as String),
        stale: response['stale'] as bool? ?? false,
      );
    } on ApiException {
      return null;
    } on NetworkException {
      return null;
    }
  }
}
