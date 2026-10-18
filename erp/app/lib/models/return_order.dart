import '../core/json_utils.dart';

/// A return order line.
class ReturnLine {
  const ReturnLine({
    required this.id,
    this.returnOrderId = '',
    required this.productId,
    this.quantity = 0,
    this.unitPrice = 0,
    this.unitCost = 0,
    this.taxRate = 0,
    this.productName,
    this.sku,
  });

  final String id;
  final String returnOrderId;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double unitCost;
  final double taxRate;
  final String? productName;
  final String? sku;

  double get lineTotal => quantity * unitPrice;

  factory ReturnLine.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    return ReturnLine(
      id: asString(json['id']),
      returnOrderId: asString(json['returnOrderId']),
      productId: asStringOrNull(json['productId']) ?? asString(product['id']),
      quantity: asInt(json['quantity']),
      unitPrice: asDouble(json['unitPrice']),
      unitCost: asDouble(json['unitCost']),
      taxRate: asDouble(json['taxRate']),
      productName: asStringOrNull(product['name']),
      sku: asStringOrNull(product['sku']),
    );
  }
}

/// A return order (customer return or supplier return).
class ReturnOrder {
  const ReturnOrder({
    required this.id,
    required this.number,
    required this.type,
    this.customerId,
    this.supplierId,
    required this.warehouseId,
    this.status = 'DRAFT',
    this.returnDate,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.total = 0,
    this.notes,
    this.customerName,
    this.supplierName,
    this.warehouseCode,
    this.warehouseName,
    this.lineCount = 0,
    this.lines = const <ReturnLine>[],
  });

  final String id;
  final String number;

  /// `CUSTOMER_RETURN` or `SUPPLIER_RETURN`.
  final String type;
  final String? customerId;
  final String? supplierId;
  final String warehouseId;
  final String status;
  final DateTime? returnDate;
  final double subtotal;
  final double taxTotal;
  final double total;
  final String? notes;
  final String? customerName;
  final String? supplierName;
  final String? warehouseCode;
  final String? warehouseName;
  final int lineCount;
  final List<ReturnLine> lines;

  bool get isCustomerReturn => type == 'CUSTOMER_RETURN';
  bool get isSupplierReturn => type == 'SUPPLIER_RETURN';
  bool get isDraft => status == 'DRAFT';
  bool get isPosted => status == 'POSTED';

  String get partnerName =>
      customerName ?? supplierName ?? (isCustomerReturn ? '—' : '—');

  factory ReturnOrder.fromJson(Map<String, dynamic> json) {
    final customer = asMap(json['customer']);
    final supplier = asMap(json['supplier']);
    final warehouse = asMap(json['warehouse']);
    final count = asMap(json['_count']);
    return ReturnOrder(
      id: asString(json['id']),
      number: asString(json['number']),
      type: asString(json['type'], fallback: 'CUSTOMER_RETURN'),
      customerId: asStringOrNull(json['customerId']),
      supplierId: asStringOrNull(json['supplierId']),
      warehouseId: asString(json['warehouseId']),
      status: asString(json['status'], fallback: 'DRAFT'),
      returnDate: asDate(json['returnDate']),
      subtotal: asDouble(json['subtotal']),
      taxTotal: asDouble(json['taxTotal']),
      total: asDouble(json['total']),
      notes: asStringOrNull(json['notes']),
      customerName: asStringOrNull(customer['name']),
      supplierName: asStringOrNull(supplier['name']),
      warehouseCode: asStringOrNull(warehouse['code']),
      warehouseName: asStringOrNull(warehouse['name']),
      lineCount: asInt(json['lineCount'], fallback: asInt(count['lines'])),
      lines: asMapList(json['lines']).map(ReturnLine.fromJson).toList(),
    );
  }
}
