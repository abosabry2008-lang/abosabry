import '../models/collection_voucher.dart';
import 'paged_list_controller.dart';

/// Paginated list of agent collection receipts (إيصالات التحصيل).
class CollectionVouchersController
    extends PagedListController<CollectionVoucher> {
  CollectionVouchersController(super.api);

  @override
  String get path => '/treasury/collections';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        // Show cancelled receipts too — the row styles them with a tag and a
        // strikethrough, and admins need the full history.
        'includeCancelled': 'true',
      };

  @override
  CollectionVoucher parseItem(Map<String, dynamic> json) =>
      CollectionVoucher.fromJson(json);
}
