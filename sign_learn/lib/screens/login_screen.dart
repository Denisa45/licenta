import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/language_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// The server answers with the same error codes Firebase Auth used.
String _authError(ApiException e) => switch (e.code) {
  'invalid-credential' || 'wrong-password' || 'user-not-found' => tr(
    'Email sau parolă greșită.',
    'Wrong email or password.',
  ),
  'email-already-in-use' => tr(
    'Există deja un cont cu acest email.',
    'An account with this email already exists.',
  ),
  'weak-password' => tr(
    'Parola trebuie să aibă minimum 6 caractere.',
    'The password needs at least 6 characters.',
  ),
  'invalid-email' => tr('Email invalid.', 'Invalid email.'),
  'network-request-failed' => tr(
    'Nu există conexiune la internet.',
    'No internet connection.',
  ),
  _ => tr(
    'Eroare de la server: ${e.code}',
    'Server error: ${e.code}',
  ),
};

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      setState(() => _error = _authError(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
    await AuthService.instance.signIn(_email.text.trim(), _password.text);
  });

  Future<void> _register() => _run(() async {
    // The server creates the user with role 'user' and signs it in.
    await AuthService.instance.register(_email.text.trim(), _password.text);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: const [LanguageButton()]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('Mână în mână', 'Hand in Hand'),
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: tr(
                      'Parolă (minimum 6 caractere)',
                      'Password (at least 6 characters)',
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(tr('Intră în cont', 'Sign in')),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _register,
                  child: Text(tr('Creează cont nou', 'Create account')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
