import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/runtime_config.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
  final configurationError = DashboardRuntimeConfig.validationError();
  var firebaseReady =
      configurationError == null && DefaultFirebaseOptions.isConfigured;
  String? initializationError = configurationError;
  if (firebaseReady) {
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    } catch (_) {
      firebaseReady = false;
      initializationError =
          'Firebase could not start. Check the deployment configuration and connection.';
    }
  }
  runApp(
    MaatriWatchApp(
      firebaseReady: firebaseReady,
      demoMode: demoMode && configurationError == null,
      initializationError: initializationError,
    ),
  );
}
