import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public Firebase web configuration comes from build-time definitions, never
/// from a service account. Example values are documented in dashboard/README.
abstract final class DefaultFirebaseOptions {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');

  static bool get isConfigured => validationError() == null;

  static String? validationError() {
    if (_apiKey.isEmpty ||
        _appId.isEmpty ||
        _messagingSenderId.isEmpty ||
        _projectId.isEmpty ||
        _authDomain.isEmpty ||
        _databaseUrl.isEmpty) {
      return 'Firebase web configuration is missing.';
    }
    if (kReleaseMode &&
        [_apiKey, _appId, _messagingSenderId, _projectId, _authDomain,
                _databaseUrl]
            .any(_unsafeReleaseValue)) {
      return 'Firebase web configuration is not safe for this release.';
    }
    final database = Uri.tryParse(_databaseUrl);
    if (kReleaseMode &&
        (database == null || database.scheme != 'https' ||
            _localHost(database.host))) {
      return 'Firebase database configuration requires HTTPS.';
    }
    return null;
  }

  static bool _unsafeReleaseValue(String value) {
    final normalised = value.trim().toLowerCase();
    return normalised.isEmpty ||
        normalised.contains('change-me') ||
        normalised.contains('your-') ||
        normalised.contains('[your') ||
        normalised.contains('<your') ||
        normalised.contains('placeholder') ||
        _localHost(normalised);
  }

  static bool _localHost(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  static FirebaseOptions get currentPlatform {
    if (!kIsWeb) {
      throw UnsupportedError('This MVP is configured for Flutter web.');
    }
    final error = validationError();
    if (error != null) {
      throw StateError(error);
    }
    return const FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      authDomain: _authDomain,
      databaseURL: _databaseUrl,
    );
  }
}
