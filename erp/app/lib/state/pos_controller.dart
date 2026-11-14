import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/product.dart';

/// A line in the POS cart.
class PosCartLine {
  PosCartLine({
    required this.product,
    this.quantity = 1,
    String? sellUnit,
    double? unitPrice,
    this.discount = 0,
  })  : sellUnit = sellUnit ??
            (product.boxesPerCarton > 0 ? 'carton' : 'unit'),
        unitPrice = unitPrice ??
            priceFor(
              product,
              sellUnit ?? (product.boxesPerCarton > 0 ? 'carton' : 'unit'),
            );

  final Product product;
  int quantity;
  /// unit | box | carton
  String sellUnit;
  double unitPrice;
  double discount;

  double get lineTotal => (quantity * unitPrice) - discount;

  double get unitFactor =>
      sellUnit == 'carton' && product.boxesPerCarton > 0
          ? product.boxesPerCarton.toDouble()
          : 1;

  int get baseQuantity => (quantity * unitFactor).round();

  static double priceFor(Product product, String unit) {
    final boxes = product.boxesPerCarton;
    if (unit == 'carton' && boxes > 0) {
      return product.cartonPrice ?? product.salePrice * boxes;
    }
    return product.boxPrice ?? product.salePrice;
  }
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
      lines.fold<int>(0, (sum, line) => sum + line.baseQuantity);

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

  void addProduct(Product product, {int quantity = 1, String? sellUnit}) {
    final unit = sellUnit ??
        (product.boxesPerCarton > 0 ? 'carton' : 'unit');
    for (final line in lines) {
      if (line.product.id == product.id && line.sellUnit == unit) {
        line.quantity += quantity;
        notifyListeners();
        return;
      }
    }
    lines.add(
      PosCartLine(product: product, quantity: quantity, sellUnit: unit),
    );
    notifyListeners();
  }

  void setQuantity(PosCartLine line, int quantity) {
    if (quantity <= 0) {
      removeLine(line);
      return;
    }
    line.quantity = quantity;
    notifyListeners();
  }

  void setUnit(PosCartLine line, String unit) {
    if (line.sellUnit == unit) return;
    final baseQty = line.baseQuantity;
    final total = line.quantity * line.unitPrice;
    final boxes = line.product.boxesPerCarton;
    line.sellUnit = unit;
    if (unit == 'carton' && boxes > 0) {
      if (baseQty >= boxes && baseQty % boxes == 0) {
        final cartons = baseQty ~/ boxes;
        line.quantity = cartons;
        line.unitPrice = total / cartons;
      } else {
        line.quantity = 1;
        line.unitPrice = PosCartLine.priceFor(line.product, 'carton');
      }
    } else {
      line.quantity = baseQty;
      line.unitPrice = baseQty <= 0
          ? PosCartLine.priceFor(line.product, 'box')
          : total / baseQty;
    }
    notifyListeners();
  }

  void setUnitPrice(PosCartLine line, double price) {
    line.unitPrice = price;
    notifyListeners();
  }

  void setDiscount(PosCartLine line, double discount) {
    line.discount = discount;
    notifyListeners();
  }

  void removeLine(PosCartLine line) {
    if (lines.remove(line)) notifyListeners();
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
                    'sellUnit': line.sellUnit,
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
