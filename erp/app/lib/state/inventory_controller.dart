import '../core/formatters.dart';
import '../models/stock_level.dart';
import '../models/stock_movement.dart';
import 'paged_list_controller.dart';

/// Stock levels (`GET /inventory/stock`).
class StockController extends PagedListController<StockLevel> {
  StockController(super.api);

  String? _warehouseId;
  String? _locationId;
  String? _productId;
  String? _categoryId;
  String _status = '';
  String _sort = 'name';

  String? get warehouseId => _warehouseId;
  String? get locationId => _locationId;
  String? get categoryId => _categoryId;

  /// '', 'in', 'low' or 'out'.
  String get status => _status;
  String get sort => _sort;

  bool get lowStockOnly => _status == 'low';

  bool get hasActiveFilters =>
      (_warehouseId != null && _warehouseId!.isNotEmpty) ||
      (_categoryId != null && _categoryId!.isNotEmpty) ||
      _status.isNotEmpty;

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
        if (_categoryId != null && _categoryId!.isNotEmpty)
          'categoryId': _categoryId,
        if (_status.isNotEmpty) 'stockStatus': _status,
        if (_sort.isNotEmpty) 'sort': _sort,
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

  void filterByCategory(String? value) {
    if (value == _categoryId) return;
    _categoryId = value;
    markFilterChanged();
    refresh();
  }

  /// Applies warehouse + category + status in one request.
  void setFilters({
    String? warehouseId,
    String? categoryId,
    String? status,
  }) {
    _warehouseId =
        (warehouseId == null || warehouseId.isEmpty) ? null : warehouseId;
    _categoryId =
        (categoryId == null || categoryId.isEmpty) ? null : categoryId;
    _status = status ?? '';
    markFilterChanged();
    refresh();
  }

  void setStatus(String value) {
    if (value == _status) return;
    _status = value;
    markFilterChanged();
    refresh();
  }

  void setLowStockOnly(bool value) {
    setStatus(value ? 'low' : '');
  }

  void setSort(String value) {
    if (value == _sort) return;
    _sort = value;
    refresh();
  }

  void resetFilters() {
    _warehouseId = null;
    _locationId = null;
    _categoryId = null;
    _status = '';
    _sort = 'name';
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
        if (_from != null) 'from': _from!.toUtc().toIso8601String(),
        if (_to != null) 'to': Formatters.isoRangeEnd(_to!),
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
