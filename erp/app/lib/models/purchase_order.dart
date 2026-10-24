import '../core/json_utils.dart';

/// A purchase order line.
class PurchaseOrderLine {
  const PurchaseOrderLine({
    required this.id,
    this.purchaseOrderId = '',
    required this.productId,
    this.quantity = 0,
    this.unitCost = 0,
    this.taxRate = 0,
    this.receivedQty = 0,
    this.productName,
    this.sku,
  });

  final String id;
  final String purchaseOrderId;
  final String productId;
  final int quantity;
  final double unitCost;
  final double taxRate;
  final int receivedQty;
  final String? productName;
  final String? sku;

  double get lineTotal => quantity * unitCost;

  int get outstanding => (quantity - receivedQty).clamp(0, quantity);

  factory PurchaseOrderLine.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    return PurchaseOrderLine(
      id: asString(json['id']),
      purchaseOrderId: asString(json['purchaseOrderId']),
      productId:
          asStringOrNull(json['productId']) ?? asString(product['id']),
      quantity: asInt(json['quantity']),
      unitCost: asDouble(json['unitCost']),
      taxRate: asDouble(json['taxRate']),
      receivedQty: asInt(json['receivedQty']),
      productName: asStringOrNull(product['name']) ??
          asStringOrNull(json['productName']),
      sku: asStringOrNull(product['sku']) ?? asStringOrNull(json['sku']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'quantity': quantity,
        'unitCost': unitCost,
        'taxRate': taxRate,
      };
}

/// A purchase order.
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.number,
    required this.supplierId,
    required this.warehouseId,
    this.currencyId,
    this.status = 'DRAFT',
    this.orderDate,
    this.expectedDate,
    this.receivedAt,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.total = 0,
    this.notes,
    this.supplierName,
    this.warehouseName,
    this.currencyCode,
    this.lines = const <PurchaseOrderLine>[],
  });

  final String id;
  final String number;
  final String supplierId;
  final String warehouseId;
  final String? currencyId;
  final String status;
  final DateTime? orderDate;
  final DateTime? expectedDate;
  final DateTime? receivedAt;
  final double subtotal;
  final double taxTotal;
  final double total;
  final String? notes;
  final String? supplierName;
  final String? warehouseName;
  final String? currencyCode;
  final List<PurchaseOrderLine> lines;

  bool get isOpen =>
      status == 'DRAFT' || status == 'PENDING' || status == 'APPROVED' ||
      status == 'PARTIALLY_RECEIVED';

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final supplier = asMap(json['supplier']);
    final warehouse = asMap(json['warehouse']);
    final currency = asMap(json['currency']);
    return PurchaseOrder(
      id: asString(json['id']),
      number: asString(json['number']),
      supplierId:
          asStringOrNull(json['supplierId']) ?? asString(supplier['id']),
      warehouseId:
          asStringOrNull(json['warehouseId']) ?? asString(warehouse['id']),
      currencyId: asStringOrNull(json['currencyId']),
      status: asString(json['status'], fallback: 'DRAFT'),
      orderDate: asDate(json['orderDate']),
      expectedDate: asDate(json['expectedDate']),
      receivedAt: asDate(json['receivedAt']),
      subtotal: asDouble(json['subtotal']),
      taxTotal: asDouble(json['taxTotal']),
      total: asDouble(json['total']),
      notes: asStringOrNull(json['notes']),
      supplierName: asStringOrNull(supplier['name']) ??
          asStringOrNull(json['supplierName']),
      warehouseName: asStringOrNull(warehouse['name']) ??
          asStringOrNull(json['warehouseName']),
      currencyCode: asStringOrNull(currency['code']) ??
          asStringOrNull(json['currencyCode']),
      lines: asMapList(json['lines']).map(PurchaseOrderLine.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'number': number,
        'supplierId': supplierId,
        'warehouseId': warehouseId,
        'currencyId': currencyId,
        'status': status,
        'orderDate': orderDate?.toUtc().toIso8601String(),
        'expectedDate': expectedDate?.toUtc().toIso8601String(),
        'notes': notes,
        'lines': lines.map((line) => line.toJson()).toList(),
      };
}
