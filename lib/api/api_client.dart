import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'session.dart';

/// The one place in the app that speaks HTTP.
///
/// Every screen goes through a repository, and every repository goes through
/// here. That is what makes "attach the token", "decode the JSON" and "turn a
/// failure into a typed exception" three problems solved once instead of
/// three problems solved badly in twenty widgets.
class ApiClient {
  ApiClient({required this.session, String? baseUrl, http.Client? httpClient})
      : baseUrl = baseUrl ?? defaultBaseUrl,
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final Session session;
  final http.Client _http;

  static const _timeout = Duration(seconds: 15);

  /// Where the backend is.
  ///
  /// The Android emulator runs behind its own NAT, so `localhost` there means
  /// the emulator itself, not the machine running the server. 10.0.2.2 is the
  /// alias the emulator provides for the host. This costs an afternoon to
  /// discover and one line to fix.
  ///
  /// In a browser there is no NAT and no emulator: the page runs on the same
  /// machine as the server, so localhost is literally correct. What the
  /// browser adds instead is the same-origin policy, which is why the server
  /// grew a CORS middleware.
  ///
  /// Override it for a real device or a deployed server with:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.0.10:3000
  static String get defaultBaseUrl {
    const fromEnvironment = String.fromEnvironment('API_BASE_URL');
    if (fromEnvironment.isNotEmpty) return fromEnvironment;

    // kIsWeb is a compile-time constant, so the tree-shaker deletes the branch
    // that does not apply. dart:io is not imported at all any more: it does
    // not exist on the web and importing it would break the build outright.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));

    request.headers['accept'] = 'application/json';

    final token = session.token;
    if (token != null) {
      request.headers['authorization'] = 'Bearer $token';
    }

    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on Object catch (error) {
      // Never reached the server. Nothing to decode, nothing to branch on.
      throw NetworkException(error);
    }

    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    // 204 No Content: a successful DELETE has nothing to say.
    if (response.statusCode == 204 || response.body.isEmpty) {
      if (_isSuccess(response.statusCode)) return null;
      throw ApiException(
        statusCode: response.statusCode,
        code: 'empty_response',
        message: 'the server answered ${response.statusCode} with no body',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        statusCode: response.statusCode,
        code: 'unexpected_response',
        message: 'the server answered something that is not JSON',
      );
    }

    if (_isSuccess(response.statusCode)) return decoded;

    throw ApiException.fromJson(
      response.statusCode,
      decoded is Map<String, dynamic> ? decoded : const {},
    );
  }

  static bool _isSuccess(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  void close() => _http.close();
}

