import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public Firebase client configuration. Values are supplied at build time;
/// service-account credentials must never be bundled in a mobile application.
abstract final class PatientFirebaseOptions {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _androidAppId =
      String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');

  static bool get isConfigured {
    if (_apiKey.isEmpty || _projectId.isEmpty || _senderId.isEmpty) {
      return false;
    }
    if (kIsWeb) return _webAppId.isNotEmpty;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidAppId.isNotEmpty,
      TargetPlatform.iOS => _iosAppId.isNotEmpty,
      _ => false,
    };
  }

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError('Firebase build-time configuration is missing.');
    }
    final appId = kIsWeb
        ? _webAppId
        : defaultTargetPlatform == TargetPlatform.android
            ? _androidAppId
            : _iosAppId;
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      authDomain: kIsWeb ? _authDomain : null,
      databaseURL: _databaseUrl.isEmpty ? null : _databaseUrl,
    );
  }
}
