import '../models/invoice.dart';
import 'day_filter.dart';
import 'paged_list_controller.dart';

/// Invoice list filtered by a mandatory day (defaults to today) and status.
class InvoicesController extends PagedListController<Invoice> {
  InvoicesController(super.api);

  String? _status;
  String? _salespersonId;
  final DayFilter dayFilter = DayFilter();

  String? get status => _status;
  String? get salespersonId => _salespersonId;

  @override
  String get path => '/invoices';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        ...dayFilter.query(),
        if (_status != null && _status!.isNotEmpty) 'status': _status,
        if (_salespersonId != null && _salespersonId!.isNotEmpty)
          'salespersonId': _salespersonId,
      };

  void filterBySalesperson(String? value) {
    if (value == _salespersonId) return;
    _salespersonId = value;
    refresh();
  }

  void filterByDay(DateTime value) {
    if (dayFilter.select(value)) refresh();
  }

  /// Refreshes whenever the list screen is reopened so documents created in
  /// another screen (or after midnight) appear without pressing search.
  @override
  Future<void> ensureLoaded() async {
    if (isInitialised) {
      await refresh();
      return;
    }
    await super.ensureLoaded();
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
