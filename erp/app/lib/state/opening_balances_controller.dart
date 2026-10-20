import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/opening_balance.dart';

/// Opening-balance entries (`GET /opening-balances`), the مديونية سابقة log.
class OpeningBalancesController extends ChangeNotifier {
  OpeningBalancesController(this.api);

  final ApiClient api;

  final List<OpeningBalance> items = <OpeningBalance>[];

  bool _loading = false;
  String? _error;
  bool _initialised = false;

  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => !_loading && items.isEmpty;
  bool get isInitialised => _initialised;

  Future<void> ensureLoaded() async {
    if (_initialised) return;
    _initialised = true;
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final rows = await api.getList('/opening-balances');
      items
        ..clear()
        ..addAll(rows.map(OpeningBalance.fromJson));
    } on ApiException catch (error) {
      _error = error.message;
    } catch (error) {
      debugPrint('OpeningBalancesController.refresh failed: $error');
      _error = 'Something went wrong while loading opening balances.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void replaceWith(OpeningBalance entry) {
    final index = items.indexWhere((item) => item.id == entry.id);
    if (index >= 0) {
      items[index] = entry;
    } else {
      items.insert(0, entry);
    }
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
