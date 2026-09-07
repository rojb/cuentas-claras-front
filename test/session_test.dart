import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitter/api/session.dart';

/// The session is the one piece of state that outlives the app, so the only
/// thing worth testing here is what comes BACK from storage — and above all
/// what happens when what comes back is incomplete.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restores a full session', () async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'a-token',
      'user_id': 'a-user',
    });

    final session = Session();
    await session.restore();

    expect(session.isLoggedIn, isTrue);
    expect(session.token, 'a-token');
    expect(session.userId, 'a-user');
  });

  test('a token without a user is not a session, and is thrown away',
      () async {
    // Exactly what a build that only stored the token leaves behind.
    FlutterSecureStorage.setMockInitialValues({'access_token': 'a-token'});

    final session = Session();
    await session.restore();

    expect(session.isLoggedIn, isFalse);
    expect(session.token, isNull);
    expect(session.userId, isNull);

    // And it is gone, so the next launch does not re-read the same orphan.
    final storage = const FlutterSecureStorage();
    expect(await storage.read(key: 'access_token'), isNull);
  });

  test('nothing stored is nobody signed in', () async {
    FlutterSecureStorage.setMockInitialValues({});

    final session = Session();
    await session.restore();

    expect(session.isLoggedIn, isFalse);
  });

  test('signing in stores both halves, signing out clears both', () async {
    FlutterSecureStorage.setMockInitialValues({});

    final session = Session();
    await session.signIn(token: 'fresh-token', userId: 'fresh-user');

    final storage = const FlutterSecureStorage();
    expect(await storage.read(key: 'access_token'), 'fresh-token');
    expect(await storage.read(key: 'user_id'), 'fresh-user');

    await session.signOut();

    expect(session.isLoggedIn, isFalse);
    expect(await storage.read(key: 'access_token'), isNull);
    expect(await storage.read(key: 'user_id'), isNull);
  });

  test('notifies listeners so the app can switch screens', () async {
    FlutterSecureStorage.setMockInitialValues({});

    final session = Session();
    var notifications = 0;
    session.addListener(() => notifications++);

    await session.signIn(token: 't', userId: 'u');
    await session.signOut();

    expect(notifications, 2);
  });
}
