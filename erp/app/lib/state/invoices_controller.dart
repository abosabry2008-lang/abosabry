import '../models/invoice.dart';
import 'day_filter.dart';
import 'paged_list_controller.dart';

/// Invoice list filtered by a mandatory day (defaults to today) and status.
class InvoicesController extends PagedListController<Invoice> {
  InvoicesController(super.api);

  String? _status;
  final DayFilter dayFilter = DayFilter();

  String? get status => _status;

  @override
  String get path => '/invoices';

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

  /// Updates a draft invoice via `PATCH /invoices/:id` and keeps the loaded
  /// list in sync. Returns the updated invoice.
  Future<Invoice> updateInvoice(
    String id,
    Map<String, dynamic> body,
  ) async {
    final data = await api.patchObject('/invoices/$id', body: body);
    final invoice = Invoice.fromJson(data);
    replaceWhere((item) => item.id == id, (_) => invoice);
    return invoice;
  }

  @override
  Invoice parseItem(Map<String, dynamic> json) => Invoice.fromJson(json);
}
