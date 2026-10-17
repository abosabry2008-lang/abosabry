import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Application level configuration.
///
/// The API base URL is compiled in from `--dart-define=API_BASE=…` (used by the
/// production web build) and can still be overridden at runtime from the login
/// screen; the override is persisted in [SharedPreferences] under the key
/// `api_base_url`.
class AppConfig {
  AppConfig._();

  /// Compile-time backend location, e.g.
  /// `flutter build web --dart-define=API_BASE=https://erp-api.onrender.com/api/v1`.
  static const String compileTimeBaseUrl =
      String.fromEnvironment('API_BASE');

  /// Fallback used when nothing was compiled in and nothing is persisted:
  /// the local dev server (Android emulators use `10.0.2.2` instead).
  static const String _devBaseUrl = 'http://localhost:4000/api/v1';

  /// Default backend location used when nothing has been persisted yet.
  static String get defaultBaseUrl =>
      compileTimeBaseUrl.isNotEmpty ? normalize(compileTimeBaseUrl) : _devBaseUrl;

  static const String _baseUrlKey = 'api_base_url';

  static String _baseUrl = defaultBaseUrl;

  /// The currently active API base URL (no trailing slash).
  static String get baseUrl => _baseUrl;

  /// Loads the persisted base URL (if any). Should be awaited in `main()`.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_baseUrlKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _baseUrl = normalize(stored);
    }
  }

  /// Persists a new base URL.
  static Future<void> setBaseUrl(String value) async {
    _baseUrl = normalize(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, _baseUrl);
  }

  /// Trims whitespace and trailing slashes; falls back to the default.
  static String normalize(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.isEmpty) return defaultBaseUrl;
    // A relative base (`/api/v1`) is resolved against the page origin on web,
    // which is how the deployed bundle talks to the API it is served by.
    if (result.startsWith('/')) {
      if (!kIsWeb) return _devBaseUrl;
      final origin = Uri.base.origin;
      return origin.isEmpty ? result : origin + result;
    }
    return result;
  }
}
