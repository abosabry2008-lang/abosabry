import '../models/stock_level.dart';
import '../models/stock_movement.dart';
import 'paged_list_controller.dart';

/// Stock levels (`GET /inventory/stock`).
class StockController extends PagedListController<StockLevel> {
  StockController(super.api);

  String? _warehouseId;
  String? _locationId;
  String? _productId;
  bool _lowStockOnly = false;

  String? get warehouseId => _warehouseId;
  String? get locationId => _locationId;
  bool get lowStockOnly => _lowStockOnly;

  @override
  String get path => '/inventory/stock';

  @override
  bool get requiresSearch => true;

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_warehouseId != null && _warehouseId!.isNotEmpty)
          'warehouseId': _warehouseId,
        if (_locationId != null && _locationId!.isNotEmpty)
          'locationId': _locationId,
        if (_productId != null && _productId!.isNotEmpty) 'productId': _productId,
        if (_lowStockOnly) 'lowStock': true,
      };

  void filterByWarehouse(String? value) {
    if (value == _warehouseId) return;
    _warehouseId = value;
    markFilterChanged();
    refresh();
  }

  void filterByLocation(String? value) {
    if (value == _locationId) return;
    _locationId = value;
    markFilterChanged();
    refresh();
  }

  void filterByProduct(String? value) {
    if (value == _productId) return;
    _productId = value;
    markFilterChanged();
    refresh();
  }

  void setLowStockOnly(bool value) {
    if (value == _lowStockOnly) return;
    _lowStockOnly = value;
    markFilterChanged();
    refresh();
  }

  @override
  StockLevel parseItem(Map<String, dynamic> json) => StockLevel.fromJson(json);
}

/// Inventory movements (`GET /inventory/movements`).
class MovementsController extends PagedListController<StockMovement> {
  MovementsController(super.api);

  String? _warehouseId;
  String? _productId;
  String? _type;
  DateTime? _from;
  DateTime? _to;

  String? get warehouseId => _warehouseId;
  String? get type => _type;

  @override
  String get path => '/inventory/movements';

  @override
  bool get requiresSearch => true;

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_warehouseId != null && _warehouseId!.isNotEmpty)
          'warehouseId': _warehouseId,
        if (_productId != null && _productId!.isNotEmpty) 'productId': _productId,
        if (_type != null && _type!.isNotEmpty) 'type': _type,
        if (_from != null) 'from': _from!.toIso8601String(),
        if (_to != null) 'to': _to!.toIso8601String(),
      };

  void filterByWarehouse(String? value) {
    if (value == _warehouseId) return;
    _warehouseId = value;
    markFilterChanged();
    refresh();
  }

  void filterByProduct(String? value) {
    if (value == _productId) return;
    _productId = value;
    markFilterChanged();
    refresh();
  }

  void filterByType(String? value) {
    if (value == _type) return;
    _type = value;
    markFilterChanged();
    refresh();
  }

  void setDateRange(DateTime? from, DateTime? to) {
    _from = from;
    _to = to;
    markFilterChanged();
    refresh();
  }

  @override
  StockMovement parseItem(Map<String, dynamic> json) =>
      StockMovement.fromJson(json);
}
