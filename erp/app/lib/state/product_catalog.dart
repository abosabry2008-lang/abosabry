import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/product.dart';

/// A cached, searchable product catalogue shared by order / POS screens.
class ProductCatalog extends ChangeNotifier {
  ProductCatalog(this.api);

  final ApiClient api;

  static const int _pageSize = 200;

  final List<Product> products = <Product>[];
  bool _loading = false;
  String? _error;
  String _search = '';
  bool _loaded = false;
  Timer? _debounce;

  bool get loading => _loading;
  String? get error => _error;
  String get search => _search;
  bool get loaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await load();
  }

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_loaded && !force) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await api.getPage<Product>(
        '/products',
        query: <String, dynamic>{
          if (_search.isNotEmpty) 'search': _search,
          'page': 1,
          'pageSize': _pageSize,
        },
        parse: Product.fromJson,
      );
      products
        ..clear()
        ..addAll(page.items);
      _loaded = true;
    } on ApiException catch (exception) {
      _error = exception.message;
    } catch (exception) {
      debugPrint('ProductCatalog.load failed: $exception');
      _error = 'Could not load products.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Debounced server-side search.
  void onSearchChanged(String value) {
    _search = value.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      load(force: true);
    });
  }

  Product? byId(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
