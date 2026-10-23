import '../models/customer.dart';
import 'paged_list_controller.dart';

/// Customer list with an optional assigned-salesperson filter.
///
/// Lists that only need to show the first page (the customers screen) use the
/// inherited paging. Form pickers need the whole book, so [ensureCatalogLoaded]
/// downloads every page once and keeps it in [catalog].
class CustomersController extends PagedListController<Customer> {
  CustomersController(super.api);

  String? _salespersonId;
  List<Customer> _catalog = <Customer>[];
  bool _catalogLoading = false;
  bool _catalogLoaded = false;

  String? get salespersonId => _salespersonId;

  /// Every active customer, for searchable pickers.
  List<Customer> get catalog => _catalog.isEmpty ? items : _catalog;

  bool get catalogLoading => _catalogLoading;

  @override
  String get path => '/customers';

  @override
  bool get requiresSearch => true;

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_salespersonId != null && _salespersonId!.isNotEmpty)
          'salespersonId': _salespersonId,
      };

  /// Loads the full customer book once (all pages, up to a safe cap).
  Future<void> ensureCatalogLoaded() async {
    if (_catalogLoaded || _catalogLoading) return;
    _catalogLoading = true;
    notifyListeners();
    try {
      final all = <Customer>[];
      var page = 1;
      while (page <= 100) {
        final result = await api.getPage<Customer>(
          '/customers',
          query: <String, dynamic>{'page': page, 'pageSize': 100},
          parse: Customer.fromJson,
        );
        all.addAll(result.items);
        if (result.items.isEmpty || page >= result.totalPages) break;
        page += 1;
      }
      _catalog = all;
      _catalogLoaded = true;
    } catch (_) {
      _catalogLoaded = false;
    } finally {
      _catalogLoading = false;
      notifyListeners();
    }
  }

  void filterBySalesperson(String? value) {
    if (value == _salespersonId) return;
    _salespersonId = value;
    markFilterChanged();
    refresh();
  }

  @override
  Customer parseItem(Map<String, dynamic> json) => Customer.fromJson(json);
}
