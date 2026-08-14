import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:maatriwatch_patient_app/core/design_tokens.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.firebaseConfigured});

  final bool firebaseConfigured;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
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

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (error) {
      setState(() => _error = _friendlyAuthError(error));
    } catch (_) {
      setState(() => _error = 'We could not sign you in. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.firebaseConfigured) return const _ConfigurationNotice();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(MaatriTokens.space24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(MaatriTokens.space32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.favorite_rounded, color: MaatriTokens.primary, size: 44),
                      const SizedBox(height: MaatriTokens.space16),
                      Text('MaatriWatch', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: MaatriTokens.space4),
                      Text(
                        'Clinician dashboard',
                        textAlign: TextAlign.center,
                        style: MaatriTokens.type(size: MaatriTokens.type16, color: MaatriTokens.textMuted),
                      ),
                      const SizedBox(height: MaatriTokens.space32),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(labelText: 'Work email'),
                        validator: (value) => value != null && value.contains('@') ? null : 'Enter your work email.',
                      ),
                      const SizedBox(height: MaatriTokens.space16),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(labelText: 'Password'),
                        validator: (value) => value != null && value.length >= 6 ? null : 'Enter your password.',
                        onFieldSubmitted: (_) => _signIn(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: MaatriTokens.space16),
                        _ErrorMessage(message: _error!),
                      ],
                      const SizedBox(height: MaatriTokens.space24),
                      ElevatedButton(
                        onPressed: _busy ? null : _signIn,
                        child: _busy
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: MaatriTokens.space16),
                      Text(
                        'Use your hospital-issued clinician account. If access is unavailable, contact your hospital administrator.',
                        textAlign: TextAlign.center,
                        style: MaatriTokens.type(size: MaatriTokens.type12, color: MaatriTokens.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfigurationNotice extends StatelessWidget {
  const _ConfigurationNotice();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(MaatriTokens.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(MaatriTokens.space24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.settings_outlined, color: MaatriTokens.warning, size: 36),
                      const SizedBox(height: MaatriTokens.space16),
                      Text('Firebase web configuration is required', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: MaatriTokens.space8),
                      const Text(
                        'This build is safe to inspect, but cannot sign in until the Firebase public web values are supplied at build time. See dashboard/README.md. No service-account credential belongs in this browser app.',
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

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(MaatriTokens.space12),
          decoration: BoxDecoration(
            color: MaatriTokens.critical.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(MaatriTokens.radius8),
          ),
          child: Text(message, style: MaatriTokens.type(size: MaatriTokens.type14, color: MaatriTokens.critical)),
        ),
      );
}

String _friendlyAuthError(FirebaseAuthException error) => switch (error.code) {
      'invalid-credential' || 'wrong-password' || 'user-not-found' => 'The email or password was not recognised.',
      'network-request-failed' => 'You appear to be offline. Reconnect and try again.',
      'too-many-requests' => 'Too many attempts. Please wait a few minutes before trying again.',
      _ => 'We could not sign you in. Please try again.',
    };
