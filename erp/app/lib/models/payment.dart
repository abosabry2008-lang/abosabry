import '../core/json_utils.dart';

/// A payment (inbound from a customer or outbound to a supplier).
class Payment {
  const Payment({
    required this.id,
    required this.number,
    this.direction = 'INBOUND',
    this.customerId,
    this.supplierId,
    this.invoiceId,
    this.currencyId,
    this.method = 'CASH',
    this.amount = 0,
    this.exchangeRate = 1,
    this.reference,
    this.note,
    this.paidAt,
    this.customerName,
    this.supplierName,
    this.invoiceNumber,
    this.currencyCode,
  });

  final String id;
  final String number;
  final String direction;
  final String? customerId;
  final String? supplierId;
  final String? invoiceId;
  final String? currencyId;
  final String method;
  final double amount;
  final double exchangeRate;
  final String? reference;
  final String? note;
  final DateTime? paidAt;
  final String? customerName;
  final String? supplierName;
  final String? invoiceNumber;
  final String? currencyCode;

  bool get isInbound => direction == 'INBOUND';

  factory Payment.fromJson(Map<String, dynamic> json) {
    final customer = asMap(json['customer']);
    final supplier = asMap(json['supplier']);
    final invoice = asMap(json['invoice']);
    final currency = asMap(json['currency']);
    return Payment(
      id: asString(json['id']),
      number: asString(json['number']),
      direction: asString(json['direction'], fallback: 'INBOUND'),
      customerId: asStringOrNull(json['customerId']),
      supplierId: asStringOrNull(json['supplierId']),
      invoiceId: asStringOrNull(json['invoiceId']),
      currencyId: asStringOrNull(json['currencyId']),
      method: asString(json['method'], fallback: 'CASH'),
      amount: asDouble(json['amount']),
      exchangeRate: asDouble(json['exchangeRate'], fallback: 1),
      reference: asStringOrNull(json['reference']),
      note: asStringOrNull(json['note']),
      paidAt: asDate(json['paidAt']),
      customerName: asStringOrNull(customer['name']) ??
          asStringOrNull(json['customerName']),
      supplierName: asStringOrNull(supplier['name']) ??
          asStringOrNull(json['supplierName']),
      invoiceNumber: asStringOrNull(invoice['number']) ??
          asStringOrNull(json['invoiceNumber']),
      currencyCode: asStringOrNull(currency['code']) ??
          asStringOrNull(json['currencyCode']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'number': number,
        'direction': direction,
        'customerId': customerId,
        'supplierId': supplierId,
        'invoiceId': invoiceId,
        'currencyId': currencyId,
        'method': method,
        'amount': amount,
        'reference': reference,
        'note': note,
        'paidAt': paidAt?.toIso8601String(),
      };
}
