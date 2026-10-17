import '../models/product.dart';
import 'paged_list_controller.dart';

/// Product list with category / low-stock filters and barcode lookup.
class ProductsController extends PagedListController<Product> {
  ProductsController(super.api);

  String? _categoryId;
  bool _lowStockOnly = false;

  String? get categoryId => _categoryId;
  bool get lowStockOnly => _lowStockOnly;

  @override
  String get path => '/products';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_categoryId != null && _categoryId!.isNotEmpty)
          'categoryId': _categoryId,
        if (_lowStockOnly) 'lowStock': true,
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
