import 'package:flutter/foundation.dart';

/// The clinician dashboard must not silently fall back to localhost in a
/// deployed browser build.
abstract final class DashboardRuntimeConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const demoMode =
      bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  static String? validationError() {
    final value = apiBaseUrl.trim();
    if (value.isEmpty) {
      return 'The dashboard API address is missing.';
    }
    final endpoint = Uri.tryParse(value);
    if (endpoint == null || endpoint.host.isEmpty) {
      return 'The dashboard API address is invalid.';
    }
    if (kReleaseMode &&
        (endpoint.scheme != 'https' ||
            _unsafeHost(endpoint.host) ||
            _placeholder(value))) {
      return 'The deployed dashboard requires a secure API connection.';
    }
    if (kReleaseMode && demoMode) {
      return 'Demo mode is blocked in a deployed clinician dashboard.';
    }
    return null;
  }

  static bool _unsafeHost(String host) {
    final value = host.trim().toLowerCase();
    return value == 'localhost' ||
        value == '127.0.0.1' ||
        value == '::1' ||
        value.contains('example') ||
        value.contains('placeholder');
  }

  static bool _placeholder(String value) {
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
