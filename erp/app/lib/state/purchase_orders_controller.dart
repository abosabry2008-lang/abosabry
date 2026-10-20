import '../models/purchase_order.dart';
import 'paged_list_controller.dart';

/// Purchase order list with supplier / status filters.
class PurchaseOrdersController extends PagedListController<PurchaseOrder> {
  PurchaseOrdersController(super.api);

  String? _status;
  String? _supplierId;

  String? get status => _status;
  String? get supplierId => _supplierId;

  @override
  String get path => '/purchase-orders';

  @override
  bool get requiresSearch => true;

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
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

  @override
  PurchaseOrder parseItem(Map<String, dynamic> json) =>
      PurchaseOrder.fromJson(json);
}
