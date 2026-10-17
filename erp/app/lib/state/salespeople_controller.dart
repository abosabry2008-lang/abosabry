import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/json_utils.dart';
import '../models/user.dart';

/// The assignable sales representatives (مناديب) — `GET /users/salespersons`.
///
/// A salesperson is any active user who is allowed to sell (their role has the
/// `sales.write` permission). The list is fetched once and cached.
class SalespeopleController extends ChangeNotifier {
  SalespeopleController(this.api);

  final ApiClient api;

  List<AppUser> salespeople = <AppUser>[];
  bool loading = false;
  String? error;

  bool _initialised = false;

  /// Loads the list the first time it is needed.
  Future<void> ensureLoaded() async {
    if (_initialised) return;
    _initialised = true;
    await load();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final json = await api.get('/users/salespersons');
      salespeople = asMapList(asMap(json)['data'])
          .map(AppUser.fromJson)
          .toList(growable: false);
    } on ApiException catch (exception) {
      error = exception.message;
    } catch (exception) {
      debugPrint('SalespeopleController.load failed: $exception');
      error = 'Could not load the salespeople.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
