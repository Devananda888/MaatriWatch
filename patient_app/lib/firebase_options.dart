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

  static bool get isConfigured => validationError() == null;

  static String? validationError() {
    if (_apiKey.isEmpty || _projectId.isEmpty || _senderId.isEmpty) {
      return 'Firebase client configuration is missing.';
    }
    final appId = kIsWeb
        ? _webAppId
        : defaultTargetPlatform == TargetPlatform.android
            ? _androidAppId
            : defaultTargetPlatform == TargetPlatform.iOS
                ? _iosAppId
                : '';
    if (appId.isEmpty) {
      return 'Firebase is not configured for this device platform.';
    }
    if (kReleaseMode &&
        [_apiKey, _projectId, _senderId, appId, _authDomain, _databaseUrl]
            .any(_isUnsafeReleaseValue)) {
      return 'Firebase client configuration is not safe for this release.';
    }
    if (kReleaseMode &&
        _databaseUrl.isNotEmpty &&
        (Uri.tryParse(_databaseUrl)?.scheme != 'https' ||
            _isLocalHost(Uri.tryParse(_databaseUrl)?.host ?? ''))) {
      return 'Firebase database configuration requires HTTPS.';
    }
    return null;
  }

  static bool _isUnsafeReleaseValue(String value) {
    final normalised = value.trim().toLowerCase();
    return normalised.isEmpty ||
        normalised.contains('change-me') ||
        normalised.contains('your-') ||
        normalised.contains('[your') ||
        normalised.contains('<your') ||
        normalised.contains('placeholder') ||
        _isLocalHost(normalised);
  }

  static bool _isLocalHost(String value) {
    final normalised = value.toLowerCase();
    return normalised == 'localhost' ||
        normalised == '127.0.0.1' ||
        normalised == '::1';
  }

  static String _appId() => kIsWeb
      ? _webAppId
      : defaultTargetPlatform == TargetPlatform.android
          ? _androidAppId
          : defaultTargetPlatform == TargetPlatform.iOS
              ? _iosAppId
              : '';

  static FirebaseOptions get currentPlatform {
    final error = validationError();
    if (error != null) {
      throw StateError(error);
    }
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId(),
      messagingSenderId: _senderId,
      projectId: _projectId,
      authDomain: kIsWeb ? _authDomain : null,
      databaseURL: _databaseUrl.isEmpty ? null : _databaseUrl,
    );
  }
}
