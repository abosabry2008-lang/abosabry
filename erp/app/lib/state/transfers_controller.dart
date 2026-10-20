import '../models/cash_transfer.dart';
import 'paged_list_controller.dart';

/// Paginated list of cash-box transfers (تحويلات الخزينة).
class TransfersController extends PagedListController<CashTransfer> {
  TransfersController(super.api);

  @override
  String get path => '/treasury/transfers';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        'paged': 'true',
        // Show cancelled transfers too so admins can review the full history;
        // the row styles them with a tag and a strikethrough.
        'includeCancelled': 'true',
      };

  @override
  CashTransfer parseItem(Map<String, dynamic> json) =>
      CashTransfer.fromJson(json);
}
