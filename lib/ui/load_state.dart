import 'package:flutter/foundation.dart';

/// What a screen knows about something it had to go and fetch.
///
/// The usual shortcut is three fields — `bool loading`, `Object? error`,
/// `T? data` — which describes eight combinations when only four of them are
/// real. Nothing stops `loading == true` alongside an error and stale data,
/// and sooner or later a widget renders exactly that.
///
/// A sealed class makes the impossible states unrepresentable, and forces
/// every `switch` to say what it draws in each one.
sealed class LoadState<T> {
  const LoadState();

  /// The value if there is one, and null while loading or after a failure.
  /// Useful for keeping the old list on screen during a pull-to-refresh.
  T? get valueOrNull => switch (this) {
        Ready<T>(:final value) => value,
        _ => null,
      };
}

/// Nothing has been asked for yet.
class Idle<T> extends LoadState<T> {
  const Idle();
}

class Loading<T> extends LoadState<T> {
  const Loading();
}

class Failed<T> extends LoadState<T> {
  const Failed(this.error);

  final Object error;
}

class Ready<T> extends LoadState<T> {
  const Ready(this.value);

  final T value;
}

/// A ChangeNotifier that owns one fetch and the state around it.
///
/// Every screen in this app needs the same five lines: set loading, notify,
/// await, catch, notify. Written once here, they stop being five chances to
/// forget a `notifyListeners()`.
class Loader<T> extends ChangeNotifier {
  Loader(this._fetch);

  final Future<T> Function() _fetch;

  LoadState<T> _state = const Idle();
  LoadState<T> get state => _state;

  bool _disposed = false;

  /// The fetch that is already running, if one is.
  ///
  /// Reloads now arrive from four directions at once — opening the screen,
  /// coming back to the app, pulling down, and a server event saying the
  /// ledger moved. Without this they would stack, and two answers landing out
  /// of order would leave the OLDER one on screen. Callers that arrive mid
  /// flight simply wait for the one already in the air.
  Future<void>? _inFlight;

  Future<void> load() =>
      _inFlight ??= _run().whenComplete(() => _inFlight = null);

  Future<void> _run() async {
    // A refresh keeps whatever is already on screen instead of blanking it,
    // so pulling to refresh does not make the list jump.
    if (_state is! Ready<T>) {
      _set(const Loading());
    }

    try {
      final value = await _fetch();
      _set(Ready(value));
    } on Object catch (error) {
      _set(Failed(error));
    }
  }

  /// Replaces the value without going to the network — after creating a group,
  /// recording a payment, anything where the answer is already in hand.
  void setValue(T value) => _set(Ready(value));

  void _set(LoadState<T> next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
