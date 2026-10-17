import '../models/sales_order.dart';
import 'paged_list_controller.dart';

/// Sales order list with customer / status filters.
class SalesOrdersController extends PagedListController<SalesOrder> {
  SalesOrdersController(super.api);

  String? _status;

  String? get status => _status;

  @override
  String get path => '/sales-orders';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_status != null && _status!.isNotEmpty) 'status': _status,
      };

  void filterByStatus(String? value) {
    if (value == _status) return;
    _status = value;
    refresh();
  }

  @override
  SalesOrder parseItem(Map<String, dynamic> json) => SalesOrder.fromJson(json);
}
