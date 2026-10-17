import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/app_settings.dart';

/// Loads and persists company settings (`GET/PATCH /settings`).
class SettingsController extends ChangeNotifier {
  SettingsController(this.api);

  final ApiClient api;

  AppSettings? settings;
  bool loading = false;
  bool saving = false;
  String? error;

  /// Currency code used for money formatting across the UI.
  String get baseCurrencyCode => settings?.baseCurrencyCode ?? 'USD';

  String? get companyName => settings?.companyName;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      settings = AppSettings.fromJson(await api.getObject('/settings'));
    } on ApiException catch (exception) {
      error = exception.message;
    } catch (exception) {
      debugPrint('SettingsController.load failed: $exception');
      error = 'Could not load settings.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> save(AppSettings next) async {
    saving = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.patchObject('/settings', body: next.toJson());
      settings = data.isEmpty ? next : AppSettings.fromJson(data);
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } catch (exception) {
      debugPrint('SettingsController.save failed: $exception');
      error = 'Could not save settings.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
