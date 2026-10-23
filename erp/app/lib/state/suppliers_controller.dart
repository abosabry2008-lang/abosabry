import '../models/supplier.dart';
import 'paged_list_controller.dart';

/// Supplier list.
///
/// [ensureCatalogLoaded] downloads every page once so searchable supplier
/// pickers are never limited to the first page.
class SuppliersController extends PagedListController<Supplier> {
  SuppliersController(super.api);

  List<Supplier> _catalog = <Supplier>[];
  bool _catalogLoading = false;
  bool _catalogLoaded = false;

  /// Every supplier, for searchable pickers.
  List<Supplier> get catalog => _catalog.isEmpty ? items : _catalog;

  bool get catalogLoading => _catalogLoading;

  @override
  String get path => '/suppliers';

  @override
  bool get requiresSearch => true;

  Future<void> ensureCatalogLoaded() async {
    if (_catalogLoaded || _catalogLoading) return;
    _catalogLoading = true;
    notifyListeners();
    try {
      final all = <Supplier>[];
      var page = 1;
      while (page <= 100) {
        final result = await api.getPage<Supplier>(
          '/suppliers',
          query: <String, dynamic>{'page': page, 'pageSize': 100},
          parse: Supplier.fromJson,
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

  @override
  Supplier parseItem(Map<String, dynamic> json) => Supplier.fromJson(json);
}
