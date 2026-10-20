import '../core/json_utils.dart';

/// Target of an account settlement (تسوية): a customer, a supplier or an
/// expense category (بند مصروف).
enum SettlementTarget { customer, supplier, expenseCategory }

/// Whether the settlement raises or lowers the target account's balance.
enum SettlementDirection { increase, decrease }

SettlementTarget settlementTargetFromApi(String? value) {
  switch (value) {
    case 'SUPPLIER':
      return SettlementTarget.supplier;
    case 'EXPENSE_CATEGORY':
      return SettlementTarget.expenseCategory;
    case 'CUSTOMER':
    default:
      return SettlementTarget.customer;
  }
}

String settlementTargetToApi(SettlementTarget value) {
  switch (value) {
    case SettlementTarget.customer:
      return 'CUSTOMER';
    case SettlementTarget.supplier:
      return 'SUPPLIER';
    case SettlementTarget.expenseCategory:
      return 'EXPENSE_CATEGORY';
  }
}

SettlementDirection settlementDirectionFromApi(String? value) =>
    value == 'DECREASE' ? SettlementDirection.decrease : SettlementDirection.increase;

String settlementDirectionToApi(SettlementDirection value) =>
    value == SettlementDirection.decrease ? 'DECREASE' : 'INCREASE';

/// A settlement (تسوية / قيد تسوية) that adjusts the balance of one account
/// without moving money in or out of any cash box.
class AccountSettlement {
  const AccountSettlement({
    required this.id,
    required this.number,
    required this.target,
    required this.direction,
    this.targetName = '',
    this.customerId,
    this.supplierId,
    this.categoryId,
    this.accountCode,
    this.amount = 0,
    this.reference,
    this.note,
    this.settledAt,
    this.userName,
    this.cancelledAt,
  });

  final String id;
  final String number;
  final SettlementTarget target;
  final SettlementDirection direction;
  final String targetName;
  final String? customerId;
  final String? supplierId;
  final String? categoryId;
  final String? accountCode;
  final double amount;
  final String? reference;
  final String? note;
  final DateTime? settledAt;
  final String? userName;
  final DateTime? cancelledAt;

  bool get cancelled => cancelledAt != null;

  factory AccountSettlement.fromJson(Map<String, dynamic> json) {
    final customer = asMap(json['customer']);
    final supplier = asMap(json['supplier']);
    final category = asMap(json['category']);
    final user = asMap(json['user']);
    final target = settlementTargetFromApi(asStringOrNull(json['target']));
    final targetName = switch (target) {
      SettlementTarget.customer => asStringOrNull(customer['name']) ?? '',
      SettlementTarget.supplier => asStringOrNull(supplier['name']) ?? '',
      SettlementTarget.expenseCategory => asStringOrNull(category['name']) ?? '',
    };
    return AccountSettlement(
      id: asString(json['id']),
      number: asString(json['number']),
      target: target,
      direction: settlementDirectionFromApi(asStringOrNull(json['direction'])),
      targetName: targetName,
      customerId: asStringOrNull(json['customerId']),
      supplierId: asStringOrNull(json['supplierId']),
      categoryId: asStringOrNull(json['categoryId']),
      accountCode: asStringOrNull(json['accountCode']),
      amount: asDouble(json['amount']),
      reference: asStringOrNull(json['reference']),
      note: asStringOrNull(json['note']),
      settledAt: asDate(json['settledAt']),
      userName: asStringOrNull(user['name']),
      cancelledAt: asDate(json['cancelledAt']),
    );
  }
}
