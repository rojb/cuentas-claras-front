import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../app/dependencies.dart';
import '../widgets/failure_view.dart';

/// Sign in and sign up on one screen.
///
/// They share every field but one, and a person who mistyped their email on
/// the sign-up form should not have to retype it after switching tabs. One
/// screen with a toggle keeps the controllers, and the text, alive.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _isRegistering = false;
  bool _busy = false;
  bool _hidePassword = true;

  /// Field errors the SERVER found, as opposed to the ones we can see from
  /// here. Cleared on every submit, because they describe one attempt.
  ApiException? _serverError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);

    final auth = Dependencies.of(context).auth;

    try {
      if (_isRegistering) {
        await auth.register(
          email: _email.text.trim(),
          password: _password.text,
          displayName: _displayName.text.trim(),
        );
      } else {
        await auth.logIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      // No navigation here on purpose: the session notifies, and the widget
      // above swaps the screen. One source of truth for "am I signed in".
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _serverError = error);
      // Re-run the validators so per-field messages from the server show up
      // underneath the fields they belong to.
      _formKey.currentState!.validate();
    } on Object catch (error) {
      if (!mounted) return;
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFailure(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(describeFailure(error))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Splitter',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gastos compartidos, cuentas claras',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 32),
                    if (_isRegistering) ...[
                      TextFormField(
                        controller: _displayName,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Decinos tu nombre'
                                : _serverError?.errorFor('displayName'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Escribí tu email';
                        }
                        if (!value.contains('@')) {
                          return 'Eso no parece un email';
                        }
                        return _serverError?.errorFor('email');
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _busy ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                        ),
                        // Length beats forced symbols, and the backend agrees:
                        // it asks for 10 characters and no punctuation rules.
                        helperText:
                            _isRegistering ? 'Al menos 10 caracteres' : null,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Escribí tu contraseña';
                        }
                        if (_isRegistering && value.length < 10) {
                          return 'Al menos 10 caracteres';
                        }
                        return _serverError?.errorFor('password');
                      },
                    ),
                    if (_serverError != null &&
                        _serverError!.details.isEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        describeFailure(_serverError!),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isRegistering ? 'Crear cuenta' : 'Entrar'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _isRegistering = !_isRegistering;
                                _serverError = null;
                              }),
                      child: Text(_isRegistering
                          ? 'Ya tengo cuenta'
                          : 'Crear una cuenta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
