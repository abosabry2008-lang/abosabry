import '../core/json_utils.dart';
import 'cash_box.dart';

/// One movement on a cash-box statement.
class BoxStatementRow {
  const BoxStatementRow({
    this.date,
    this.type = 'PAYMENT_IN',
    this.direction = 'IN',
    this.number = '',
    this.description = '',
    this.amount = 0,
    this.balance = 0,
    this.method,
    this.reference,
    this.paymentId,
    this.transferId,
  });

  final DateTime? date;

  /// `PAYMENT_IN`, `PAYMENT_OUT`, `TRANSFER_IN` or `TRANSFER_OUT`.
  final String type;

  /// `IN` or `OUT`.
  final String direction;
  final String number;
  final String description;
  final double amount;
  final double balance;
  final String? method;
  final String? reference;
  final String? paymentId;
  final String? transferId;

  bool get isIn => direction == 'IN';
  bool get isPayment => paymentId != null;
  bool get isTransfer => transferId != null;

  factory BoxStatementRow.fromJson(Map<String, dynamic> json) => BoxStatementRow(
        date: asDate(json['date']),
        type: asString(json['type'], fallback: 'PAYMENT_IN'),
        direction: asString(json['direction'], fallback: 'IN'),
        number: asString(json['number']),
        description: asString(json['description']),
        amount: asDouble(json['amount']),
        balance: asDouble(json['balance']),
        method: asStringOrNull(json['method']),
        reference: asStringOrNull(json['reference']),
        paymentId: asStringOrNull(json['paymentId']),
        transferId: asStringOrNull(json['transferId']),
      );
}

/// Statement of account (كشف حساب) for a single cash box over a date range.
class BoxStatement {
  const BoxStatement({
    required this.box,
    this.from,
    this.to,
    this.openingBalance = 0,
    this.closingBalance = 0,
    this.inTotal = 0,
    this.outTotal = 0,
    this.rows = const <BoxStatementRow>[],
  });

  final CashBox box;
  final DateTime? from;
  final DateTime? to;
  final double openingBalance;
  final double closingBalance;
  final double inTotal;
  final double outTotal;
  final List<BoxStatementRow> rows;

  factory BoxStatement.fromJson(Map<String, dynamic> json) {
    final box = asMapOrNull(json['box']);
    return BoxStatement(
      box: CashBox(
        id: box == null ? '' : asString(box['id']),
        code: box == null ? '' : asString(box['code']),
        name: box == null ? '' : asString(box['name']),
        type: box == null ? 'SUB' : asString(box['type'], fallback: 'SUB'),
        openingBalance: box == null ? 0 : asDouble(box['openingBalance']),
        balance: asDouble(json['closingBalance']),
      ),
      from: asDate(json['from']),
      to: asDate(json['to']),
      openingBalance: asDouble(json['openingBalance']),
      closingBalance: asDouble(json['closingBalance']),
      inTotal: asDouble(json['inTotal']),
      outTotal: asDouble(json['outTotal']),
      rows: asMapList(json['rows']).map(BoxStatementRow.fromJson).toList(),
    );
  }
}
