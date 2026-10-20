import '../models/account_settlement.dart';
import 'paged_list_controller.dart';

/// Paginated list of account settlements (التسويات).
class SettlementsController extends PagedListController<AccountSettlement> {
  SettlementsController(super.api);

  SettlementTarget? _target;

  SettlementTarget? get target => _target;

  @override
  String get path => '/settlements';

  @override
  bool get requiresSearch => true;

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_target != null) 'target': settlementTargetToApi(_target!),
        // Admins need the full history, cancellations included.
        'includeCancelled': 'true',
      };

  void filterByTarget(SettlementTarget? value) {
    if (value == _target) return;
    _target = value;
    markFilterChanged();
    refresh();
  }

  @override
  AccountSettlement parseItem(Map<String, dynamic> json) =>
      AccountSettlement.fromJson(json);
}
