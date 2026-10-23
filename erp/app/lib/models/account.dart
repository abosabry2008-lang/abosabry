import '../core/json_utils.dart';

/// A general-ledger account.
class Account {
  const Account({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.active = true,
    this.debit = 0,
    this.credit = 0,
  });

  final String id;
  final String code;
  final String name;
  final String type;
  final bool active;
  final double debit;
  final double credit;

  /// Signed balance: positive is a debit balance, negative is a credit balance.
  double get balance => debit - credit;

  static const List<String> types = <String>[
    'ASSET',
    'LIABILITY',
    'EQUITY',
    'REVENUE',
    'EXPENSE',
  ];

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: asString(json['id']),
        code: asString(json['code']),
        name: asString(json['name']),
        type: asString(json['type'], fallback: 'ASSET'),
        active: asBool(json['active'], fallback: true),
        debit: asDouble(json['debit']),
        credit: asDouble(json['credit']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'code': code,
        'name': name,
        'type': type,
        'active': active,
      };
}
