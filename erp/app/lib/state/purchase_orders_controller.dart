import '../models/purchase_order.dart';
import 'day_filter.dart';
import 'paged_list_controller.dart';

/// Purchase order list with supplier / status / day filters.
class PurchaseOrdersController extends PagedListController<PurchaseOrder> {
  PurchaseOrdersController(super.api);

  String? _status;
  String? _supplierId;
  final DayFilter dayFilter = DayFilter();

  String? get status => _status;
  String? get supplierId => _supplierId;

  @override
  String get path => '/purchase-orders';

  @override
  bool get requiresSearch => false;

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        ...dayFilter.query(),
        if (_status != null && _status!.isNotEmpty) 'status': _status,
        if (_supplierId != null && _supplierId!.isNotEmpty)
          'supplierId': _supplierId,
      };

  void filterByStatus(String? value) {
    if (value == _status) return;
    _status = value;
    markFilterChanged();
    refresh();
  }

  void filterBySupplier(String? value) {
    if (value == _supplierId) return;
    _supplierId = value;
    markFilterChanged();
    refresh();
  }

  void filterByDay(DateTime value) {
    if (dayFilter.select(value)) refresh();
  }

  @override
  PurchaseOrder parseItem(Map<String, dynamic> json) =>
      PurchaseOrder.fromJson(json);
}
