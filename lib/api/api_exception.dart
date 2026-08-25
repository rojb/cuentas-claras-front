/// One field the server rejected, and why.
class FieldError {
  const FieldError({required this.field, required this.message});

  final String field;
  final String message;

  factory FieldError.fromJson(Map<String, dynamic> json) => FieldError(
        field: json['field'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );
}

/// An error the backend meant to send.
///
/// The API answers every failure with the same shape:
///
///     {"error": {"code": "...", "message": "...", "details": [...]}}
///
/// `code` is the part that matters. A message is for a human to read; a code
/// is for the app to act on. Branching on message text is how you ship a bug
/// the day somebody fixes a typo on the server.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details = const [],
  });

  final int statusCode;
  final String code;
  final String message;
  final List<FieldError> details;

  /// The token is gone or expired: the only correct answer is to log out.
  bool get requiresLogIn =>
      statusCode == 401 &&
      (code == 'missing_token' ||
          code == 'invalid_token' ||
          code == 'token_expired');

  /// The request was well formed and the numbers still do not work out —
  /// percentages that add up to 66%, items that do not match the total. Worth
  /// separating, because this one is the user's arithmetic, not their typing.
  bool get isImpossible => statusCode == 422;

  /// The message for a given field, if the server complained about it.
  String? errorFor(String field) {
    for (final detail in details) {
      if (detail.field == field) return detail.message;
    }
    return null;
  }

  factory ApiException.fromJson(int statusCode, Map<String, dynamic> body) {
    final error = body['error'];

    if (error is! Map<String, dynamic>) {
      return ApiException(
        statusCode: statusCode,
        code: 'unexpected_response',
        message: 'the server answered something we did not understand',
      );
    }

    final details = error['details'];

    return ApiException(
      statusCode: statusCode,
      code: error['code'] as String? ?? 'unknown_error',
      message: error['message'] as String? ?? 'something went wrong',
      details: details is List
          ? details
              .whereType<Map<String, dynamic>>()
              .map(FieldError.fromJson)
              .toList()
          : const [],
    );
  }

  @override
  String toString() => 'ApiException($statusCode $code): $message';
}

/// The request never reached the server: no signal, server down, timeout.
///
/// Deliberately not an ApiException. There is no code to branch on and no
/// field to highlight — the only sensible reaction is "try again", and the
/// type system should say so instead of leaving the UI to guess.
class NetworkException implements Exception {
  const NetworkException(this.cause);

  final Object cause;

  @override
  String toString() => 'NetworkException: $cause';
}
