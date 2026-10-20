import '../models/customer.dart';
import 'paged_list_controller.dart';

/// Customer list with an optional assigned-salesperson filter.
class CustomersController extends PagedListController<Customer> {
  CustomersController(super.api);

  String? _salespersonId;

  String? get salespersonId => _salespersonId;

  @override
  String get path => '/customers';

  @override
  bool get requiresSearch => true;

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_salespersonId != null && _salespersonId!.isNotEmpty)
          'salespersonId': _salespersonId,
      };

  void filterBySalesperson(String? value) {
    if (value == _salespersonId) return;
    _salespersonId = value;
    markFilterChanged();
    refresh();
  }

  @override
  Customer parseItem(Map<String, dynamic> json) => Customer.fromJson(json);
}
