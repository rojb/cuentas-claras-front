import '../api/api_client.dart';
import '../api/session.dart';
import '../models/user.dart';

/// Registering and logging in.
///
/// A repository owns one slice of the API and hands back models, never raw
/// maps. Widgets should not know that `displayName` is spelled that way, and
/// they certainly should not know what a status code is.
class AuthRepository {
  const AuthRepository(this._api, this._session);

  final ApiClient _api;
  final Session _session;

  Future<User> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _api.post('/auth/register', body: {
      'email': email,
      'password': password,
      'displayName': displayName,
    }) as Map<String, dynamic>;

    return _startSession(response);
  }

  Future<User> logIn({
    required String email,
    required String password,
  }) async {
    final response = await _api.post('/auth/login', body: {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;

    return _startSession(response);
  }

  /// Who the stored token belongs to. Throws a 401 if it has expired, which
  /// is how the app finds out to send somebody back to the login screen.
  Future<User> currentUser() async {
    final response = await _api.get('/auth/me') as Map<String, dynamic>;
    return User.fromJson(response['user'] as Map<String, dynamic>);
  }

  Future<void> logOut() => _session.signOut();

  /// The token is saved before the user is returned, so by the time a screen
  /// reacts to a successful login the next request already carries it.
  Future<User> _startSession(Map<String, dynamic> response) async {
    await _session.signIn(response['accessToken'] as String);
    return User.fromJson(response['user'] as Map<String, dynamic>);
  }
}
