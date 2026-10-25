import '../models/collection_voucher.dart';
import 'day_filter.dart';
import 'paged_list_controller.dart';

/// Paginated list of agent collection receipts (إيصالات التحصيل).
class CollectionVouchersController
    extends PagedListController<CollectionVoucher> {
  CollectionVouchersController(super.api);

  final DayFilter dayFilter = DayFilter();

  @override
  String get path => '/treasury/collections';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        ...dayFilter.query(),
        // Show cancelled receipts too — the row styles them with a tag and a
        // strikethrough, and admins need the full history.
        'includeCancelled': 'true',
      };

  void filterByDay(DateTime value) {
    if (dayFilter.select(value)) refresh();
  }

  /// Refreshes when the tab is reopened so new receipts appear immediately.
  @override
  Future<void> ensureLoaded() async {
    if (isInitialised) {
      await refresh();
      return;
    }
    await super.ensureLoaded();
  }

  @override
  CollectionVoucher parseItem(Map<String, dynamic> json) =>
      CollectionVoucher.fromJson(json);
}
