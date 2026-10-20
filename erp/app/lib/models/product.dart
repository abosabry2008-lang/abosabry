import '../core/json_utils.dart';

/// A sellable / stockable product.
class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    this.barcode,
    this.description,
    this.categoryId,
    this.categoryName,
    this.currencyId,
    this.currencyCode,
    this.unit = 'pc',
    this.costPrice = 0,
    this.salePrice = 0,
    this.taxRate = 0,
    this.reorderLevel = 0,
    this.trackInventory = true,
    this.active = true,
    this.imageUrl,
    this.deletedAt,
    this.quantityOnHand,
  });

  final String id;
  final String sku;
  final String name;
  final String? barcode;
  final String? description;
  final String? categoryId;
  final String? categoryName;
  final String? currencyId;
  final String? currencyCode;
  final String unit;
  final double costPrice;
  final double salePrice;
  final double taxRate;
  final int reorderLevel;
  final bool trackInventory;
  final bool active;
  final String? imageUrl;

  /// When set, the product was deleted and only appears with "show deleted".
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  /// Aggregated on-hand quantity when the API provides it.
  final int? quantityOnHand;

  bool get isLowStock =>
      quantityOnHand != null && quantityOnHand! <= reorderLevel;

  factory Product.fromJson(Map<String, dynamic> json) {
    final category = asMap(json['category']);
    final currency = asMap(json['currency']);
    return Product(
      id: asString(json['id']),
      sku: asString(json['sku']),
      name: asString(json['name']),
      barcode: asStringOrNull(json['barcode']),
      description: asStringOrNull(json['description']),
      categoryId:
          asStringOrNull(json['categoryId']) ?? asStringOrNull(category['id']),
      categoryName: asStringOrNull(category['name']) ??
          asStringOrNull(json['categoryName']),
      currencyId: asStringOrNull(json['currencyId']),
      currencyCode: asStringOrNull(currency['code']) ??
          asStringOrNull(json['currencyCode']),
      unit: asString(json['unit'], fallback: 'pc'),
      costPrice: asDouble(json['costPrice']),
      salePrice: asDouble(json['salePrice']),
      taxRate: asDouble(json['taxRate']),
      reorderLevel: asInt(json['reorderLevel']),
      trackInventory: asBool(json['trackInventory'], fallback: true),
      active: asBool(json['active'], fallback: true),
      imageUrl: asStringOrNull(json['imageUrl']),
      deletedAt: asDate(json['deletedAt']),
      quantityOnHand: _parseQuantity(json),
    );
  }

  static int? _parseQuantity(Map<String, dynamic> json) {
    final direct = asIntOrNull(json['quantity']) ??
        asIntOrNull(json['quantityOnHand']) ??
        asIntOrNull(json['stock']) ??
        asIntOrNull(json['onHand']);
    if (direct != null) return direct;
    final levels = json['stockLevels'];
    if (levels is List) {
      var total = 0;
      var found = false;
      for (final level in levels) {
        final map = asMap(level);
        if (map.isEmpty) continue;
        total += asInt(map['quantity']);
        found = true;
      }
      return found ? total : null;
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sku': sku,
        'name': name,
        'barcode': barcode,
        'description': description,
        'categoryId': categoryId,
        'currencyId': currencyId,
        'unit': unit,
        'costPrice': costPrice,
        'salePrice': salePrice,
        'taxRate': taxRate,
        'reorderLevel': reorderLevel,
        'trackInventory': trackInventory,
        'active': active,
        'imageUrl': imageUrl,
      };
}
