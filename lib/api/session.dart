import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Who is signed in: the token, and the person it belongs to.
///
/// The two are one value on purpose. A token on its own is enough to CALL the
/// API and not enough to read the answers: half the screens in an app about
/// money eventually need "which of these rows is mine", and a balance list
/// where you cannot find yourself is a list of strangers. Keeping them in a
/// single record makes the half-session unrepresentable instead of leaving
/// every caller to remember that one of them might be missing.
typedef Identity = ({String token, String userId});

/// Where the session lives between app launches.
///
/// flutter_secure_storage, not shared_preferences. A JWT is a credential: on
/// Android it goes into the Keystore, on iOS into the Keychain, both backed
/// by hardware. shared_preferences is a plain file — fine for "dark mode is
/// on", wrong for something that opens somebody's account.
///
/// It is a ValueNotifier as well, so the widget tree can rebuild the moment
/// the session appears or disappears. Logging out is then one line, and there
/// is no way to have a screen still showing while the session is gone.
class Session extends ValueNotifier<Identity?> {
  Session({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        super(null);

  static const _tokenKey = 'access_token';
  static const _userIdKey = 'user_id';

  final FlutterSecureStorage _storage;

  bool get isLoggedIn => value != null;
  String? get token => value?.token;

  /// The signed-in user's id, for screens that need to tell them apart from
  /// everybody else in a group. Null when nobody is signed in.
  String? get userId => value?.userId;

  /// Reads whatever was stored last time the app ran. Call once at startup.
  ///
  /// Half an identity is treated as none, and thrown away. A build that only
  /// ever stored the token leaves exactly that behind, and honouring it would
  /// mean carrying a "signed in but nameless" state through the whole app to
  /// save one login. The cost of the strict version is one re-login, once.
  Future<void> restore() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final userId = await _storage.read(key: _userIdKey);

      if (token == null || userId == null) {
        value = null;
        // Do not leave the orphan behind to be re-read on every launch.
        if (token != null || userId != null) await _clear();
        return;
      }

      value = (token: token, userId: userId);
    } on Exception {
      // A keystore that cannot be read is not a reason to refuse to start.
      // The worst case is the person logs in again.
      value = null;
    }
  }

  Future<void> signIn({required String token, required String userId}) async {
    value = (token: token, userId: userId);

    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: userId);
  }

  Future<void> signOut() async {
    value = null;
    await _clear();
  }

  Future<void> _clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
  }
}
