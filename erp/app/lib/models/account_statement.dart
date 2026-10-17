import '../core/json_utils.dart';

/// A single ledger entry of an account statement.
class StatementRow {
  const StatementRow({
    this.date,
    this.type = 'INVOICE',
    this.number = '',
    this.description = '',
    this.debit = 0,
    this.credit = 0,
    this.balance = 0,
  });

  final DateTime? date;

  /// `INVOICE` or `PAYMENT`.
  final String type;
  final String number;
  final String description;
  final double debit;
  final double credit;
  final double balance;

  factory StatementRow.fromJson(Map<String, dynamic> json) => StatementRow(
        date: asDate(json['date']),
        type: asString(json['type'], fallback: 'INVOICE'),
        number: asString(json['number']),
        description: asString(json['description']),
        debit: asDouble(json['debit']),
        credit: asDouble(json['credit']),
        balance: asDouble(json['balance']),
      );
}

/// Customer / supplier account statement
/// (`GET /reports/{customers|suppliers}/:id/statement`).
class AccountStatement {
  const AccountStatement({
    this.name = '',
    this.email,
    this.phone,
    this.address,
    this.balance = 0,
    this.creditLimit = 0,
    this.from,
    this.to,
    this.openingBalance = 0,
    this.rows = const <StatementRow>[],
    this.totalDebit = 0,
    this.totalCredit = 0,
    this.closingBalance = 0,
  });

  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final double balance;
  final double creditLimit;
  final DateTime? from;
  final DateTime? to;
  final double openingBalance;
  final List<StatementRow> rows;
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;

  factory AccountStatement.fromJson(Map<String, dynamic> json) {
    final partner = asMap(json['customer'] ?? json['supplier']);
    final totals = asMap(json['totals']);
    return AccountStatement(
      name: asString(partner['name'], fallback: 'Account'),
      email: asStringOrNull(partner['email']),
      phone: asStringOrNull(partner['phone']),
      address: asStringOrNull(partner['address']),
      balance: asDouble(partner['balance']),
      creditLimit: asDouble(partner['creditLimit']),
      from: asDate(json['from']),
      to: asDate(json['to']),
      openingBalance: asDouble(json['openingBalance']),
      rows: asMapList(json['rows']).map(StatementRow.fromJson).toList(),
      totalDebit: asDouble(totals['debit']),
      totalCredit: asDouble(totals['credit']),
      closingBalance: asDouble(totals['closingBalance']),
    );
  }
}
