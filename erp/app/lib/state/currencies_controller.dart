import '../models/currency.dart';
import 'paged_list_controller.dart';

/// Currency list.
class CurrenciesController extends PagedListController<Currency> {
  CurrenciesController(super.api);

  @override
  String get path => '/currencies';

  @override
  Currency parseItem(Map<String, dynamic> json) => Currency.fromJson(json);
}
