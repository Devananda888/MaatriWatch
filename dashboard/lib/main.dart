import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
  var firebaseReady = DefaultFirebaseOptions.isConfigured;
  String? initializationError;
  if (firebaseReady) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (_) {
      firebaseReady = false;
      initializationError = 'Firebase could not start. Check the deployment configuration and connection.';
    }
  }
  runApp(
    MaatriWatchApp(
      firebaseReady: firebaseReady,
      demoMode: demoMode,
      initializationError: initializationError,
    ),
  );
}
