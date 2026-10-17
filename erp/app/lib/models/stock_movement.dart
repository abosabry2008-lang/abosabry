import '../core/json_utils.dart';

/// A signed inventory movement.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.type,
    required this.productId,
    required this.locationId,
    required this.warehouseId,
    this.quantity = 0,
    this.unitCost = 0,
    this.balanceAfter,
    this.reference,
    this.note,
    this.productName,
    this.sku,
    this.locationCode,
    this.warehouseName,
    this.userName,
    this.createdAt,
  });

  final String id;
  final String type;
  final String productId;
  final String locationId;
  final String warehouseId;
  final int quantity;
  final double unitCost;
  final int? balanceAfter;
  final String? reference;
  final String? note;
  final String? productName;
  final String? sku;
  final String? locationCode;
  final String? warehouseName;
  final String? userName;
  final DateTime? createdAt;

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    final location = asMap(json['location']);
    final warehouse = asMap(json['warehouse']);
    final user = asMap(json['user']);
    return StockMovement(
      id: asString(json['id']),
      type: asString(json['type']),
      productId:
          asStringOrNull(json['productId']) ?? asString(product['id']),
      locationId:
          asStringOrNull(json['locationId']) ?? asString(location['id']),
      warehouseId:
          asStringOrNull(json['warehouseId']) ?? asString(warehouse['id']),
      quantity: asInt(json['quantity']),
      unitCost: asDouble(json['unitCost']),
      balanceAfter: asIntOrNull(json['balanceAfter']),
      reference: asStringOrNull(json['reference']),
      note: asStringOrNull(json['note']),
      productName: asStringOrNull(product['name']) ??
          asStringOrNull(json['productName']),
      sku: asStringOrNull(product['sku']) ?? asStringOrNull(json['sku']),
      locationCode: asStringOrNull(location['code']) ??
          asStringOrNull(json['locationCode']),
      warehouseName: asStringOrNull(warehouse['name']) ??
          asStringOrNull(json['warehouseName']),
      userName:
          asStringOrNull(user['name']) ?? asStringOrNull(json['userName']),
      createdAt: asDate(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'productId': productId,
        'locationId': locationId,
        'warehouseId': warehouseId,
        'quantity': quantity,
        'unitCost': unitCost,
        'balanceAfter': balanceAfter,
        'reference': reference,
        'note': note,
      };
}
