import '../core/json_utils.dart';

/// A sales order line.
class SalesOrderLine {
  const SalesOrderLine({
    required this.id,
    this.salesOrderId = '',
    required this.productId,
    this.quantity = 0,
    this.unitPrice = 0,
    this.discount = 0,
    this.taxRate = 0,
    this.fulfilledQty = 0,
    this.productName,
    this.sku,
    this.sellUnit = 'unit',
  });

  final String id;
  final String salesOrderId;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double discount;
  final double taxRate;
  final int fulfilledQty;
  final String? productName;
  final String? sku;
  final String sellUnit;

  double get lineTotal => (quantity * unitPrice) - discount;

  int get outstanding => (quantity - fulfilledQty).clamp(0, quantity);

  factory SalesOrderLine.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    return SalesOrderLine(
      id: asString(json['id']),
      salesOrderId: asString(json['salesOrderId']),
      productId:
          asStringOrNull(json['productId']) ?? asString(product['id']),
      quantity: asInt(json['quantity']),
      unitPrice: asDouble(json['unitPrice']),
      discount: asDouble(json['discount']),
      taxRate: asDouble(json['taxRate']),
      fulfilledQty: asInt(json['fulfilledQty']),
      productName: asStringOrNull(product['name']) ??
          asStringOrNull(json['productName']),
      sku: asStringOrNull(product['sku']) ?? asStringOrNull(json['sku']),
      sellUnit: asString(json['sellUnit'], fallback: 'unit'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'discount': discount,
        'taxRate': taxRate,
        if (sellUnit != 'unit') 'sellUnit': sellUnit,
      };
}

/// A sales order.
class SalesOrder {
  const SalesOrder({
    required this.id,
    required this.number,
    this.customerId,
    required this.warehouseId,
    this.currencyId,
    this.status = 'DRAFT',
    this.channel = 'MANUAL',
    this.orderDate,
    this.fulfilledAt,
    this.subtotal = 0,
    this.discountTotal = 0,
    this.taxTotal = 0,
    this.total = 0,
    this.paidAmount = 0,
    this.paymentCashBoxId,
    this.paymentCashBoxName,
    this.paymentMethod = 'CASH',
    this.notes,
    this.customerName,
    this.warehouseName,
    this.currencyCode,
    this.lines = const <SalesOrderLine>[],
  });

  final String id;
  final String number;
  final String? customerId;
  final String warehouseId;
  final String? currencyId;
  final String status;
  final String channel;
  final DateTime? orderDate;
  final DateTime? fulfilledAt;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final double paidAmount;
  final String? paymentCashBoxId;
  final String? paymentCashBoxName;
  final String paymentMethod;
  final String? notes;
  final String? customerName;
  final String? warehouseName;
  final String? currencyCode;
  final List<SalesOrderLine> lines;

  bool get isOpen =>
      status == 'DRAFT' || status == 'CONFIRMED' || status == 'PARTIALLY_FULFILLED';

  factory SalesOrder.fromJson(Map<String, dynamic> json) {
    final customer = asMap(json['customer']);
    final warehouse = asMap(json['warehouse']);
    final currency = asMap(json['currency']);
    return SalesOrder(
      id: asString(json['id']),
      number: asString(json['number']),
      customerId: asStringOrNull(json['customerId']),
      warehouseId:
          asStringOrNull(json['warehouseId']) ?? asString(warehouse['id']),
      currencyId: asStringOrNull(json['currencyId']),
      status: asString(json['status'], fallback: 'DRAFT'),
      channel: asString(json['channel'], fallback: 'MANUAL'),
      orderDate: asDate(json['orderDate']),
      fulfilledAt: asDate(json['fulfilledAt']),
      subtotal: asDouble(json['subtotal']),
      discountTotal: asDouble(json['discountTotal']),
      taxTotal: asDouble(json['taxTotal']),
      total: asDouble(json['total']),
      paidAmount: asDouble(json['paidAmount']),
      paymentCashBoxId: asStringOrNull(json['paymentCashBoxId']),
      paymentCashBoxName:
          asStringOrNull(asMap(json['paymentCashBox'])['name']),
      paymentMethod: asString(json['paymentMethod'], fallback: 'CASH'),
      notes: asStringOrNull(json['notes']),
      customerName: asStringOrNull(customer['name']) ??
          asStringOrNull(json['customerName']),
      warehouseName: asStringOrNull(warehouse['name']) ??
          asStringOrNull(json['warehouseName']),
      currencyCode: asStringOrNull(currency['code']) ??
          asStringOrNull(json['currencyCode']),
      lines: asMapList(json['lines']).map(SalesOrderLine.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'number': number,
        'customerId': customerId,
        'warehouseId': warehouseId,
        'currencyId': currencyId,
        'status': status,
        'channel': channel,
        'orderDate': orderDate?.toUtc().toIso8601String(),
        'paidAmount': paidAmount,
        'paymentCashBoxId': paymentCashBoxId,
        'paymentMethod': paymentMethod,
        'notes': notes,
        'lines': lines.map((line) => line.toJson()).toList(),
      };
}
