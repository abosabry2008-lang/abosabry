import '../models/sales_order.dart';
import 'day_filter.dart';
import 'paged_list_controller.dart';

/// Sales order list filtered by a mandatory day (defaults to today) and status.
class SalesOrdersController extends PagedListController<SalesOrder> {
  SalesOrdersController(super.api);

  String? _status;
  final DayFilter dayFilter = DayFilter();

  String? get status => _status;

  @override
  String get path => '/sales-orders';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        ...dayFilter.query(),
        if (_status != null && _status!.isNotEmpty) 'status': _status,
      };

  void filterByDay(DateTime value) {
    if (dayFilter.select(value)) refresh();
  }

  void filterByStatus(String? value) {
    if (value == _status) return;
    _status = value;
    refresh();
  }

  @override
  SalesOrder parseItem(Map<String, dynamic> json) => SalesOrder.fromJson(json);
}
