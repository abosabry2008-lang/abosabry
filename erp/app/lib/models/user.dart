import '../core/json_utils.dart';

/// A user account (`/auth/*`, `/users`).
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.phone,
    this.active = true,
    this.lastLoginAt,
    this.createdAt,
  });

  final String id;
  final String email;
  final String name;
  final String role;
  final String? phone;
  final bool active;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: asString(json['id']),
        email: asString(json['email']),
        name: asString(json['name']),
        role: asString(json['role'], fallback: 'SALES'),
        phone: asStringOrNull(json['phone']),
        active: asBool(json['active'], fallback: true),
        lastLoginAt: asDate(json['lastLoginAt']),
        createdAt: asDate(json['createdAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'email': email,
        'name': name,
        'role': role,
        'phone': phone,
        'active': active,
      };
}
