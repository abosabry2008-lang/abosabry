import '../core/json_utils.dart';

/// A supplier / vendor.
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.contact,
    this.email,
    this.phone,
    this.address,
    this.taxId,
    this.paymentTermDays = 30,
    this.balance = 0,
    this.active = true,
  });

  final String id;
  final String name;
  final String? contact;
  final String? email;
  final String? phone;
  final String? address;
  final String? taxId;
  final int paymentTermDays;
  final double balance;
  final bool active;

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: asString(json['id']),
        name: asString(json['name']),
        contact: asStringOrNull(json['contact']),
        email: asStringOrNull(json['email']),
        phone: asStringOrNull(json['phone']),
        address: asStringOrNull(json['address']),
        taxId: asStringOrNull(json['taxId']),
        paymentTermDays: asInt(json['paymentTermDays'], fallback: 30),
        balance: asDouble(json['balance']),
        active: asBool(json['active'], fallback: true),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'contact': contact,
        'email': email,
        'phone': phone,
        'address': address,
        'taxId': taxId,
        'paymentTermDays': paymentTermDays,
        'active': active,
      };
}
