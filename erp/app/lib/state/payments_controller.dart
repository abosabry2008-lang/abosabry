import '../models/payment.dart';
import 'paged_list_controller.dart';

/// Payment list with an optional direction filter.
class PaymentsController extends PagedListController<Payment> {
  PaymentsController(super.api);

  String? _direction;

  String? get direction => _direction;

  @override
  String get path => '/payments';

  @override
  bool get requiresSearch => true;

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_direction != null && _direction!.isNotEmpty) 'direction': _direction,
      };

  void filterByDirection(String? value) {
    if (value == _direction) return;
    _direction = value;
    markFilterChanged();
    refresh();
  }

  @override
  Payment parseItem(Map<String, dynamic> json) => Payment.fromJson(json);
}
