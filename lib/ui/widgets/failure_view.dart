import 'package:flutter/material.dart';

import '../../api/api_exception.dart';

/// Turns whatever went wrong into something a person can act on.
///
/// One place, because the alternative is every screen inventing its own
/// wording for the same three failures — and eventually one of them showing
/// a raw stack trace to a user.
///
/// The wording lives HERE and not on the server. The API answers with a
/// stable `code` and an English message; the code is the contract, the
/// message is a courtesy. Translating on the client means the backend never
/// has to know what language anybody speaks, and a second client in another
/// language costs nothing on the server.
String describeFailure(Object error) => switch (error) {
      NetworkException() =>
        'No se pudo conectar con el servidor. Revisá tu conexión y probá de '
            'nuevo.',
      ApiException(requiresLogIn: true) =>
        'Tu sesión venció. Iniciá sesión de nuevo.',
      ApiException(statusCode: >= 500) =>
        'Algo se rompió de nuestro lado. Probá de nuevo en un momento.',
      // Falls back to the server's own message for a code we have not
      // translated: English is worse than Spanish, and both beat silence.
      ApiException(:final code, :final message) => _byCode[code] ?? message,
      _ => 'Algo salió mal.',
    };

const _byCode = <String, String>{
  'email_taken': 'Ese email ya está registrado.',
  'invalid_credentials': 'El email o la contraseña no son correctos.',
  'group_not_found': 'Ese grupo no existe.',
  'user_not_found': 'No hay nadie registrado con ese email.',
  'expense_not_found': 'Ese gasto ya no existe.',
  'payment_not_found': 'Ese pago ya no existe.',
  'payment_to_self': 'Un pago va de una persona a otra distinta.',
  'not_a_member': 'Esa persona no está en el grupo.',
  'invalid_split': 'Las cuentas no cierran: la división no suma el total.',
  'invalid_body': 'Faltan datos o están mal escritos.',
  'route_not_found': 'Esa dirección no existe en el servidor.',

  // Not from the server: ApiClient invents these when the answer is not
  // something it can decode. The English text inside the exception stays put
  // for logs — this is the version a person reads.
  'empty_response': 'El servidor contestó sin contenido.',
  'unexpected_response': 'El servidor contestó algo que no entendimos.',
  'unknown_error': 'Algo salió mal.',
};

class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error is NetworkException ? Icons.wifi_off : Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              describeFailure(error),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The empty state: not an error, just nothing here yet.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
