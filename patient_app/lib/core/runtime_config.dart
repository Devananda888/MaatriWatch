import 'package:flutter/foundation.dart';

/// Build-time settings shared by the patient application.
///
/// No endpoint is inferred at runtime: a release build without an explicit,
/// HTTPS API endpoint is intentionally blocked before a user can sign in.
abstract final class PatientRuntimeConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const demoMode =
      bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  static String? validationError() {
    final value = apiBaseUrl.trim();
    if (value.isEmpty) {
      return 'This app has not been configured. Please install the hospital-issued version.';
    }
    final endpoint = Uri.tryParse(value);
    if (endpoint == null || !endpoint.hasScheme || endpoint.host.isEmpty) {
      return 'This app has an invalid service address. Please contact your care team.';
    }
    if (kReleaseMode &&
        (endpoint.scheme != 'https' ||
            _isLocalOrPlaceholder(endpoint.host) ||
            _isPlaceholder(value))) {
      return 'This release requires a secure service connection.';
    }
    if (kReleaseMode && demoMode) {
      return 'Demo mode is not available in the patient release.';
    }
    return null;
  }

  static bool _isLocalOrPlaceholder(String host) {
    final normalised = host.trim().toLowerCase();
    return normalised == 'localhost' ||
        normalised == '127.0.0.1' ||
        normalised == '::1' ||
        normalised.contains('example') ||
        normalised.contains('placeholder');
  }

  static bool _isPlaceholder(String value) {
    final normalised = value.toLowerCase();
    return normalised.contains('change-me') ||
        normalised.contains('your-') ||
        normalised.contains('[your') ||
        normalised.contains('<your');
  }

  static Uri get apiUri {
    final error = validationError();
    if (error != null) throw StateError(error);
    return Uri.parse(apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), ''));
  }
}
