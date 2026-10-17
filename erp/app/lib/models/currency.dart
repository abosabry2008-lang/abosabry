import '../core/json_utils.dart';

/// A currency definition with its rate against the base currency.
class Currency {
  const Currency({
    required this.id,
    required this.code,
    required this.name,
    this.symbol = r'$',
    this.exchangeRate = 1,
    this.isBase = false,
    this.active = true,
  });

  final String id;
  final String code;
  final String name;
  final String symbol;
  final double exchangeRate;
  final bool isBase;
  final bool active;

  factory Currency.fromJson(Map<String, dynamic> json) => Currency(
        id: asString(json['id']),
        code: asString(json['code']),
        name: asString(json['name']),
        symbol: asString(json['symbol'], fallback: r'$'),
        exchangeRate: asDouble(json['exchangeRate'], fallback: 1),
        isBase: asBool(json['isBase']),
        active: asBool(json['active'], fallback: true),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'code': code,
        'name': name,
        'symbol': symbol,
        'exchangeRate': exchangeRate,
        'isBase': isBase,
        'active': active,
      };
}
