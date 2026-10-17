import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/json_utils.dart';
import '../models/warehouse.dart';
import 'paged_list_controller.dart';

/// Warehouse list.
class WarehousesController extends PagedListController<Warehouse> {
  WarehousesController(super.api);

  @override
  String get path => '/warehouses';

  @override
  Warehouse parseItem(Map<String, dynamic> json) => Warehouse.fromJson(json);
}

/// Locations of a single warehouse (`GET /warehouses/:id/locations`).
///
/// The endpoint always requires a warehouse id, so this controller is not
/// backed by [PagedListController].
class LocationsController extends ChangeNotifier {
  LocationsController(this.api);

  final ApiClient api;

  final List<Location> items = <Location>[];
  bool _loading = false;
  String? _error;
  String? _warehouseId;

  bool get loading => _loading;
  String? get error => _error;
  String? get warehouseId => _warehouseId;
  bool get isEmpty => !_loading && items.isEmpty;

  Future<void> load(String warehouseId) async {
    _warehouseId = warehouseId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await api.get('/warehouses/$warehouseId/locations');
      items
        ..clear()
        ..addAll(_extract(data).map(Location.fromJson));
    } on ApiException catch (error) {
      _error = error.message;
    } catch (error) {
      debugPrint('LocationsController.load failed: $error');
      _error = 'Could not load locations.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    final id = _warehouseId;
    if (id == null) return;
    await load(id);
  }

  Iterable<Map<String, dynamic>> _extract(dynamic json) {
    final root = asMap(json);
    final data = root['data'];
    if (data is List) return asMapList(data);
    if (json is List) return asMapList(json);
    return const <Map<String, dynamic>>[];
  }
}
