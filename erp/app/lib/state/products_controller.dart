import '../models/product.dart';
import 'paged_list_controller.dart';

/// Product list with category / low-stock filters and barcode lookup.
class ProductsController extends PagedListController<Product> {
  ProductsController(super.api);

  String? _categoryId;
  bool _lowStockOnly = false;
  bool _showInactive = false;
  bool _showDeleted = false;

  String? get categoryId => _categoryId;
  bool get lowStockOnly => _lowStockOnly;
  bool get showInactive => _showInactive;
  bool get showDeleted => _showDeleted;

  @override
  String get path => '/products';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_categoryId != null && _categoryId!.isNotEmpty)
          'categoryId': _categoryId,
        if (_lowStockOnly) 'lowStock': true,
        if (_showInactive || _showDeleted) 'includeInactive': true,
        if (_showDeleted) 'includeDeleted': true,
      };

  void filterByCategory(String? value) {
    if (value == _categoryId) return;
    _categoryId = value;
    refresh();
  }

  void setLowStockOnly(bool value) {
    if (value == _lowStockOnly) return;
    _lowStockOnly = value;
    refresh();
  }

  /// Shows products that were deactivated (and, via [showDeleted], deleted).
  void setShowInactive(bool value) {
    if (value == _showInactive) return;
    _showInactive = value;
    refresh();
  }

  void setShowDeleted(bool value) {
    if (value == _showDeleted) return;
    _showDeleted = value;
    if (value) _showInactive = true;
    refresh();
  }

  /// `POST /products/:id/restore` — brings a deleted product back.
  Future<void> restore(String id) async {
    await api.post('/products/$id/restore', body: const <String, dynamic>{});
    await refresh();
  }

  /// `DELETE /products/:id`
  Future<void> delete(String id) async {
    await api.delete('/products/$id');
    removeWhere((item) => item.id == id);
  }

  @override
  Product parseItem(Map<String, dynamic> json) => Product.fromJson(json);

  /// `GET /products/barcode/:code`
  Future<Product> findByBarcode(String code) async {
    final data = await api.getObject(
      '/products/barcode/${Uri.encodeComponent(code.trim())}',
    );
    return Product.fromJson(data);
  }
}
