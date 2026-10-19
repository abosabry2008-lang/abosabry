import '../core/json_utils.dart';

/// A single customer/invoice line of an agent collection receipt (إيصال تحصيل).
class CollectionLine {
  const CollectionLine({
    this.id = '',
    this.customerId,
    this.customerName = '',
    this.invoiceId,
    this.invoiceNumber,
    this.cashBoxId,
    this.cashBoxName = '',
    this.amount = 0,
    this.note,
  });

  final String id;
  final String? customerId;
  final String customerName;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? cashBoxId;
  final String cashBoxName;
  final double amount;
  final String? note;

  factory CollectionLine.fromJson(Map<String, dynamic> json) {
    final customer = asMapOrNull(json['customer']);
    final invoice = asMapOrNull(json['invoice']);
    final box = asMapOrNull(json['cashBox']);
    return CollectionLine(
      id: asString(json['id']),
      customerId: asStringOrNull(json['customerId']),
      customerName: customer == null ? '' : asString(customer['name']),
      invoiceId: asStringOrNull(json['invoiceId']),
      invoiceNumber: invoice == null ? null : asStringOrNull(invoice['number']),
      cashBoxId: asStringOrNull(json['cashBoxId']) ??
          (box == null ? null : asStringOrNull(box['id'])),
      cashBoxName: box == null ? '' : asString(box['name']),
      amount: asDouble(json['amount']),
      note: asStringOrNull(json['note']),
    );
  }
}

/// A receipt an agent (مندوب) hands in for several customers at once.
class CollectionVoucher {
  const CollectionVoucher({
    required this.id,
    required this.number,
    this.cashBoxId,
    this.cashBoxName = '',
    this.salespersonId,
    this.salespersonName = '',
    this.userName = '',
    this.collectedAt,
    this.reference,
    this.note,
    this.total = 0,
    this.cancelledAt,
    this.lines = const <CollectionLine>[],
    this.paymentNumbers = const <String>[],
  });

  final String id;
  final String number;
  final String? cashBoxId;
  final String cashBoxName;
  final String? salespersonId;
  final String salespersonName;
  final String userName;
  final DateTime? collectedAt;
  final String? reference;
  final String? note;
  final double total;
  final DateTime? cancelledAt;
  final List<CollectionLine> lines;
  final List<String> paymentNumbers;

  bool get cancelled => cancelledAt != null;

  factory CollectionVoucher.fromJson(Map<String, dynamic> json) {
    final box = asMapOrNull(json['cashBox']);
    final salesperson = asMapOrNull(json['salesperson']);
    final user = asMapOrNull(json['user']);
    return CollectionVoucher(
      id: asString(json['id']),
      number: asString(json['number']),
      cashBoxId: asStringOrNull(json['cashBoxId']),
      cashBoxName: box == null ? '' : asString(box['name']),
      salespersonId: asStringOrNull(json['salespersonId']),
      salespersonName: salesperson == null ? '' : asString(salesperson['name']),
      userName: user == null ? '' : asString(user['name']),
      collectedAt: asDate(json['collectedAt']),
      reference: asStringOrNull(json['reference']),
      note: asStringOrNull(json['note']),
      total: asDouble(json['total']),
      cancelledAt: asDate(json['cancelledAt']),
      lines: asMapList(json['lines']).map(CollectionLine.fromJson).toList(),
      paymentNumbers: asMapList(json['payments'])
          .map((payment) => asString(payment['number']))
          .where((number) => number.isNotEmpty)
          .toList(),
    );
  }
}
