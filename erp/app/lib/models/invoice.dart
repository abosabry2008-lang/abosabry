import '../core/json_utils.dart';

/// An invoice line.
class InvoiceLine {
  const InvoiceLine({
    required this.id,
    this.invoiceId = '',
    this.productId,
    this.description = '',
    this.quantity = 0,
    this.unitPrice = 0,
    this.discount = 0,
    this.taxRate = 0,
    this.total = 0,
    this.sellUnit = 'unit',
    this.unitCost = 0,
  });

  final String id;
  final String invoiceId;
  final String? productId;
  final String description;
  final int quantity;
  final double unitPrice;
  final double discount;
  final double taxRate;
  final double total;
  final String sellUnit;
  /// Product cost per unit, used for profit (managers and admins only).
  final double unitCost;

  /// Revenue before tax: quantity × price minus the line discount.
  double get netRevenue => quantity * unitPrice - discount;

  double get profit => netRevenue - quantity * unitCost;

  factory InvoiceLine.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    return InvoiceLine(
      id: asString(json['id']),
      invoiceId: asString(json['invoiceId']),
      productId: asStringOrNull(json['productId']),
      description: asString(
        json['description'] ?? product['name'],
      ),
      quantity: asInt(json['quantity']),
      unitPrice: asDouble(json['unitPrice']),
      discount: asDouble(json['discount']),
      taxRate: asDouble(json['taxRate']),
      total: asDouble(json['total']),
      sellUnit: asString(json['sellUnit'], fallback: 'unit'),
      unitCost: asDoubleOrNull(json['unitCost']) ??
          asDouble(product['costPrice']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'description': description,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'discount': discount,
        'taxRate': taxRate,
        if (sellUnit != 'unit') 'sellUnit': sellUnit,
      };
}

/// An invoice.
class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    this.customerId,
    this.salesOrderId,
    this.currencyId,
    this.status = 'DRAFT',
    this.issueDate,
    this.dueDate,
    this.subtotal = 0,
    this.discountTotal = 0,
    this.taxTotal = 0,
    this.total = 0,
    this.amountPaid = 0,
    this.balance = 0,
    this.previousBalance = 0,
    this.exchangeRate = 1,
    this.notes,
    this.customerName,
    this.salesOrderNumber,
    this.currencyCode,
    this.lines = const <InvoiceLine>[],
  });

  final String id;
  final String number;
  final String? customerId;
  final String? salesOrderId;
  final String? currencyId;
  final String status;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final double amountPaid;
  final double balance;
  /// What the customer owed before this invoice (open balance on their other
  /// documents plus any opening balance). Shown on screen and on the print.
  final double previousBalance;
  final double exchangeRate;
  final String? notes;
  final String? customerName;
  final String? salesOrderNumber;
  final String? currencyCode;
  final List<InvoiceLine> lines;

  bool get canIssue => status == 'DRAFT';
  /// Admins may void any live invoice, including a paid one (the API cancels
  /// its payments first). The only exception is a receipt-paid invoice, which
  /// must have its collection receipt cancelled first.
  bool get canVoid => status != 'VOID';
  bool get isOverdue {
    if (status == 'PAID' || status == 'VOID' || dueDate == null) return false;
    return balance > 0 && dueDate!.isBefore(DateTime.now());
  }

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final customer = asMap(json['customer']);
    final currency = asMap(json['currency']);
    final salesOrder = asMap(json['salesOrder']);
    return Invoice(
      id: asString(json['id']),
      number: asString(json['number']),
      customerId: asStringOrNull(json['customerId']),
      salesOrderId: asStringOrNull(json['salesOrderId']),
      currencyId: asStringOrNull(json['currencyId']),
      status: asString(json['status'], fallback: 'DRAFT'),
      issueDate: asDate(json['issueDate']),
      dueDate: asDate(json['dueDate']),
      subtotal: asDouble(json['subtotal']),
      discountTotal: asDouble(json['discountTotal']),
      taxTotal: asDouble(json['taxTotal']),
      total: asDouble(json['total']),
      amountPaid: asDouble(json['amountPaid']),
      balance: asDouble(json['balance']),
      previousBalance: asDouble(json['previousBalance']),
      exchangeRate: asDouble(json['exchangeRate'], fallback: 1),
      notes: asStringOrNull(json['notes']),
      customerName: asStringOrNull(customer['name']) ??
          asStringOrNull(json['customerName']),
      salesOrderNumber: asStringOrNull(salesOrder['number']) ??
          asStringOrNull(json['salesOrderNumber']),
      currencyCode: asStringOrNull(currency['code']) ??
          asStringOrNull(json['currencyCode']),
      lines: asMapList(json['lines']).map(InvoiceLine.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'number': number,
        'customerId': customerId,
        'salesOrderId': salesOrderId,
        'currencyId': currencyId,
        'status': status,
        'issueDate': issueDate?.toUtc().toIso8601String(),
        'dueDate': dueDate?.toUtc().toIso8601String(),
        'notes': notes,
        'lines': lines.map((line) => line.toJson()).toList(),
      };
}
