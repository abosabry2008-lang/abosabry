import '../models/payment.dart';
import 'day_filter.dart';
import 'paged_list_controller.dart';

/// Payment list filtered by a mandatory day (defaults to today) and direction.
class PaymentsController extends PagedListController<Payment> {
  PaymentsController(super.api);

  String? _direction;
  final DayFilter dayFilter = DayFilter();

  String? get direction => _direction;

  @override
  String get path => '/payments';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        ...dayFilter.query(),
        if (_direction != null && _direction!.isNotEmpty) 'direction': _direction,
      };

  void filterByDay(DateTime value) {
    if (dayFilter.select(value)) refresh();
  }

  void filterByDirection(String? value) {
    if (value == _direction) return;
    _direction = value;
    refresh();
  }

  @override
  Payment parseItem(Map<String, dynamic> json) => Payment.fromJson(json);
}
