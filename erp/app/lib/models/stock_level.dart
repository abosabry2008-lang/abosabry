import '../core/json_utils.dart';

/// On-hand quantity for a product at a given location.
class StockLevel {
  const StockLevel({
    required this.id,
    required this.productId,
    required this.locationId,
    required this.warehouseId,
    this.quantity = 0,
    this.reserved = 0,
    this.productName,
    this.sku,
    this.locationCode,
    this.warehouseName,
    this.reorderLevel = 0,
    this.updatedAt,
  });

  final String id;
  final String productId;
  final String locationId;
  final String warehouseId;
  final int quantity;
  final int reserved;
  final String? productName;
  final String? sku;
  final String? locationCode;
  final String? warehouseName;
  final int reorderLevel;
  final DateTime? updatedAt;

  int get available => quantity - reserved;

  bool get isLowStock => reorderLevel > 0 && quantity <= reorderLevel;

  factory StockLevel.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    final location = asMap(json['location']);
    final warehouse = asMap(json['warehouse']);
    return StockLevel(
      id: asString(json['id']),
      productId:
          asStringOrNull(json['productId']) ?? asString(product['id']),
      locationId:
          asStringOrNull(json['locationId']) ?? asString(location['id']),
      warehouseId:
          asStringOrNull(json['warehouseId']) ?? asString(warehouse['id']),
      quantity: asInt(json['quantity']),
      reserved: asInt(json['reserved']),
      productName: asStringOrNull(product['name']) ??
          asStringOrNull(json['productName']),
      sku: asStringOrNull(product['sku']) ?? asStringOrNull(json['sku']),
      locationCode: asStringOrNull(location['code']) ??
          asStringOrNull(json['locationCode']),
      warehouseName: asStringOrNull(warehouse['name']) ??
          asStringOrNull(json['warehouseName']),
      reorderLevel: asInt(
        product['reorderLevel'] ?? json['reorderLevel'],
      ),
      updatedAt: asDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'productId': productId,
        'locationId': locationId,
        'warehouseId': warehouseId,
        'quantity': quantity,
        'reserved': reserved,
      };
}
