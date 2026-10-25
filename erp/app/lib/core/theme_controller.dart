import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and exposes the user's light/dark theme choice.
///
/// The default is light; the chosen mode is stored under `app_theme_mode` so it
/// survives reloads on web and restarts on mobile.
class ThemeController extends ChangeNotifier {
  static const String _key = 'app_theme_mode';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  /// Loads the persisted mode (if any). Should be awaited during startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored == 'dark') {
      _mode = ThemeMode.dark;
      notifyListeners();
    } else if (stored == 'light') {
      _mode = ThemeMode.light;
      notifyListeners();
    }
  }

  /// Switches to [mode] and persists the choice.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == ThemeMode.dark ? 'dark' : 'light');
  }

  /// Flips between light and dark and persists the new choice.
  Future<void> toggle() =>
      setMode(isDark ? ThemeMode.light : ThemeMode.dark);
}
