import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the access token lives between app launches.
///
/// flutter_secure_storage, not shared_preferences. A JWT is a credential: on
/// Android it goes into the Keystore, on iOS into the Keychain, both backed
/// by hardware. shared_preferences is a plain file — fine for "dark mode is
/// on", wrong for something that opens somebody's account.
///
/// It is a ValueNotifier as well, so the widget tree can rebuild the moment
/// the token appears or disappears. Logging out is then one line, and there
/// is no way to have a screen still showing while the session is gone.
class Session extends ValueNotifier<String?> {
  Session({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        super(null);

  static const _tokenKey = 'access_token';

  final FlutterSecureStorage _storage;

  bool get isLoggedIn => value != null;
  String? get token => value;

  /// Reads whatever was stored last time the app ran. Call once at startup.
  Future<void> restore() async {
    try {
      value = await _storage.read(key: _tokenKey);
    } on Exception {
      // A keystore that cannot be read is not a reason to refuse to start.
      // The worst case is the person logs in again.
      value = null;
    }
  }

  Future<void> signIn(String token) async {
    value = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> signOut() async {
    value = null;
    await _storage.delete(key: _tokenKey);
  }
}
