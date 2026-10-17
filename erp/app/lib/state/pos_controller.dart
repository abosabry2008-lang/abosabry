import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/product.dart';

/// A line in the POS cart.
class PosCartLine {
  PosCartLine({
    required this.product,
    this.quantity = 1,
    double? unitPrice,
    this.discount = 0,
  }) : unitPrice = unitPrice ?? product.salePrice;

  final Product product;
  int quantity;
  double unitPrice;
  double discount;

  double get lineTotal => (quantity * unitPrice) - discount;
}

/// State for the point-of-sale screen.
class PosController extends ChangeNotifier {
  PosController(this.api);

  final ApiClient api;

  final List<PosCartLine> lines = <PosCartLine>[];

  String? customerId;
  String? warehouseId;
  String method = 'CASH';
  bool submitting = false;
  String? error;

  int get itemCount =>
      lines.fold<int>(0, (sum, line) => sum + line.quantity);

  double get subtotal =>
      lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  double get total => subtotal;

  bool get isEmpty => lines.isEmpty;

  void setWarehouse(String? id) {
    if (id == warehouseId) return;
    warehouseId = id;
    notifyListeners();
  }

  void setCustomer(String? id) {
    if (id == customerId) return;
    customerId = id;
    notifyListeners();
  }

  void setMethod(String value) {
    if (value == method) return;
    method = value;
    notifyListeners();
  }

  void addProduct(Product product, {int quantity = 1}) {
    for (final line in lines) {
      if (line.product.id == product.id) {
        line.quantity += quantity;
        notifyListeners();
        return;
      }
    }
    lines.add(PosCartLine(product: product, quantity: quantity));
    notifyListeners();
  }

  void setQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }
    for (final line in lines) {
      if (line.product.id == productId) {
        line.quantity = quantity;
        notifyListeners();
        return;
      }
    }
  }

  void setUnitPrice(String productId, double price) {
    for (final line in lines) {
      if (line.product.id == productId) {
        line.unitPrice = price;
        notifyListeners();
        return;
      }
    }
  }

  void setDiscount(String productId, double discount) {
    for (final line in lines) {
      if (line.product.id == productId) {
        line.discount = discount;
        notifyListeners();
        return;
      }
    }
  }

  void removeProduct(String productId) {
    final before = lines.length;
    lines.removeWhere((line) => line.product.id == productId);
    if (lines.length != before) notifyListeners();
  }

  void clear() {
    lines.clear();
    customerId = null;
    error = null;
    notifyListeners();
  }

  /// `POST /pos/sale`
  Future<Map<String, dynamic>?> submit({required double paidAmount}) async {
    if (lines.isEmpty) {
      error = 'Add at least one product to the sale.';
      notifyListeners();
      return null;
    }
    if (warehouseId == null || warehouseId!.isEmpty) {
      error = 'Select a warehouse before completing the sale.';
      notifyListeners();
      return null;
    }
    submitting = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.postObject(
        '/pos/sale',
        body: <String, dynamic>{
          if (customerId != null && customerId!.isNotEmpty)
            'customerId': customerId,
          'warehouseId': warehouseId,
          'lines': lines
              .map((line) => <String, dynamic>{
                    'productId': line.product.id,
                    'quantity': line.quantity,
                    'unitPrice': line.unitPrice,
                    'discount': line.discount,
                  })
              .toList(),
          'method': method,
          'paidAmount': paidAmount,
        },
      );
      lines.clear();
      customerId = null;
      return data;
    } on ApiException catch (exception) {
      error = exception.message;
      return null;
    } catch (exception) {
      debugPrint('PosController.submit failed: $exception');
      error = 'Could not complete the sale.';
      return null;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }
}
