import '../core/json_utils.dart';

/// An expense category (تصنيف مصروف) — e.g. rent, salaries, utilities.
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    this.accountId,
    this.accountCode,
    this.accountName,
    this.active = true,
    this.expenseCount = 0,
  });

  final String id;
  final String name;
  final String? accountId;
  final String? accountCode;
  final String? accountName;
  final bool active;
  final int expenseCount;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    final account = asMap(json['account']);
    final count = asMap(json['_count']);
    return ExpenseCategory(
      id: asString(json['id']),
      name: asString(json['name']),
      accountId: asStringOrNull(json['accountId']),
      accountCode: asStringOrNull(account['code']),
      accountName: asStringOrNull(account['name']),
      active: asBool(json['active'], fallback: true),
      expenseCount: asInt(count['expenses']),
    );
  }
}

/// A recorded expense (مصروف) — a cash outflow from a box to a non-party payee.
class Expense {
  const Expense({
    required this.id,
    required this.number,
    this.categoryId,
    this.categoryName,
    this.cashBoxId,
    this.cashBoxName = '',
    this.accountCode,
    this.amount = 0,
    this.method = 'CASH',
    this.payee,
    this.reference,
    this.note,
    this.spentAt,
    this.userName,
    this.cancelledAt,
  });

  final String id;
  final String number;
  final String? categoryId;
  final String? categoryName;
  final String? cashBoxId;
  final String cashBoxName;
  final String? accountCode;
  final double amount;
  final String method;
  final String? payee;
  final String? reference;
  final String? note;
  final DateTime? spentAt;
  final String? userName;
  final DateTime? cancelledAt;

  bool get cancelled => cancelledAt != null;

  factory Expense.fromJson(Map<String, dynamic> json) {
    final category = asMap(json['category']);
    final cashBox = asMap(json['cashBox']);
    final user = asMap(json['user']);
    return Expense(
      id: asString(json['id']),
      number: asString(json['number']),
      categoryId: asStringOrNull(json['categoryId']),
      categoryName: asStringOrNull(category['name']),
      cashBoxId: asStringOrNull(json['cashBoxId']),
      cashBoxName: asStringOrNull(cashBox['name']) ?? '',
      accountCode: asStringOrNull(json['accountCode']),
      amount: asDouble(json['amount']),
      method: asString(json['method'], fallback: 'CASH'),
      payee: asStringOrNull(json['payee']),
      reference: asStringOrNull(json['reference']),
      note: asStringOrNull(json['note']),
      spentAt: asDate(json['spentAt']),
      userName: asStringOrNull(user['name']),
      cancelledAt: asDate(json['cancelledAt']),
    );
  }
}
