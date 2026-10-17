import '../core/json_utils.dart';

/// A general-ledger account.
class Account {
  const Account({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.active = true,
  });

  final String id;
  final String code;
  final String name;
  final String type;
  final bool active;

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
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'code': code,
        'name': name,
        'type': type,
        'active': active,
      };
}
