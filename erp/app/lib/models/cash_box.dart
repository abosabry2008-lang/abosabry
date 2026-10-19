import '../core/json_utils.dart';

/// A cash box (خزنة) — a main till or a sub box such as a branch drawer.
///
/// `balance` is computed by the API from the box's opening balance plus every
/// live payment and transfer, so it always reflects cancellations and edits.
class CashBox {
  const CashBox({
    required this.id,
    required this.code,
    required this.name,
    this.type = 'SUB',
    this.openingBalance = 0,
    this.balance = 0,
    this.active = true,
    this.isDefault = false,
  });

  final String id;
  final String code;
  final String name;

  /// `MAIN` or `SUB`.
  final String type;
  final double openingBalance;
  final double balance;
  final bool active;
  final bool isDefault;

  bool get isMain => type == 'MAIN';

  factory CashBox.fromJson(Map<String, dynamic> json) => CashBox(
        id: asString(json['id']),
        code: asString(json['code']),
        name: asString(json['name']),
        type: asString(json['type'], fallback: 'SUB'),
        openingBalance: asDouble(json['openingBalance']),
        balance: asDouble(json['balance'], fallback: asDouble(json['openingBalance'])),
        active: asBool(json['active'], fallback: true),
        isDefault: asBool(json['isDefault']),
      );
}
