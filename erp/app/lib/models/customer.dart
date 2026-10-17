import '../core/json_utils.dart';

/// A customer / buyer.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.taxId,
    this.creditLimit = 0,
    this.balance = 0,
    this.active = true,
    this.salespersonId,
    this.salespersonName,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? taxId;
  final double creditLimit;
  final double balance;
  final bool active;

  /// Assigned sales representative (مندوب), if any.
  final String? salespersonId;
  final String? salespersonName;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: asString(json['id']),
        name: asString(json['name']),
        email: asStringOrNull(json['email']),
        phone: asStringOrNull(json['phone']),
        address: asStringOrNull(json['address']),
        taxId: asStringOrNull(json['taxId']),
        creditLimit: asDouble(json['creditLimit']),
        balance: asDouble(json['balance']),
        active: asBool(json['active'], fallback: true),
        salespersonId: asStringOrNull(json['salespersonId']),
        salespersonName:
            asStringOrNull(asMap(json['salesperson'])['name']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'address': address,
        'taxId': taxId,
        'creditLimit': creditLimit,
        'active': active,
        'salespersonId': salespersonId,
      };
}
