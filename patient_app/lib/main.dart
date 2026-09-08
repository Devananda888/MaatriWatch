import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'core/runtime_config.dart';
import 'features/auth/auth_gate.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configurationError = PatientRuntimeConfig.validationError();
  var firebaseReady =
      configurationError == null && PatientFirebaseOptions.isConfigured;
  String? initializationError = configurationError;
  if (firebaseReady) {
    try {
      await Firebase.initializeApp(
          options: PatientFirebaseOptions.currentPlatform);
    } catch (_) {
      firebaseReady = false;
      initializationError =
          'MaatriWatch could not start securely. Check the hospital-issued app configuration and connection.';
    }
  } else {
    initializationError ??=
        'This app has not been configured for a patient account.';
  }
  runApp(MaatriWatchPatientApp(
      firebaseReady: firebaseReady, initializationError: initializationError));
}

/// Android-first entry point for the MaatriWatch companion app.
class MaatriWatchPatientApp extends StatelessWidget {
  const MaatriWatchPatientApp({
    super.key,
    this.firebaseReady = false,
    this.initializationError,
    this.home,
  });

  final bool firebaseReady;
  final String? initializationError;
  final Widget? home;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MaatriWatch',
        debugShowCheckedModeBanner: false,
        theme: maatriTheme(),
        home: home ??
            (firebaseReady
                ? PatientAuthGate(auth: FirebaseAuth.instance)
                : _ConfigurationScreen(message: initializationError)),
      );
}

class _ConfigurationScreen extends StatelessWidget {
  const _ConfigurationScreen({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.admin_panel_settings_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text('MaatriWatch setup needed',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    message ?? 'This app is not ready to connect securely.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Please contact your hospital care team. Do not use an unconfigured app for care decisions.',
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
