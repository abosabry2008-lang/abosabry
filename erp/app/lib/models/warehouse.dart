import '../core/json_utils.dart';

/// A physical warehouse.
class Warehouse {
  const Warehouse({
    required this.id,
    required this.code,
    required this.name,
    this.address,
    this.phone,
    this.active = true,
    this.locationCount = 0,
    this.locations = const <Location>[],
  });

  final String id;
  final String code;
  final String name;
  final String? address;
  final String? phone;
  final bool active;
  final int locationCount;
  final List<Location> locations;

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
        id: asString(json['id']),
        code: asString(json['code']),
        name: asString(json['name']),
        address: asStringOrNull(json['address']),
        phone: asStringOrNull(json['phone']),
        active: asBool(json['active'], fallback: true),
        locationCount: asInt(
          json['locationCount'] ?? asMap(json['_count'])['locations'],
          fallback: asRawList(json['locations']).length,
        ),
        locations: asMapList(json['locations']).map(Location.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'code': code,
        'name': name,
        'address': address,
        'phone': phone,
        'active': active,
      };
}

/// A bin / shelf / location inside a [Warehouse].
class Location {
  const Location({
    required this.id,
    required this.warehouseId,
    required this.code,
    this.name,
    this.active = true,
    this.warehouseName,
  });

  final String id;
  final String warehouseId;
  final String code;
  final String? name;
  final bool active;
  final String? warehouseName;

  String get label =>
      (name == null || name!.isEmpty) ? code : '$code — $name';

  factory Location.fromJson(Map<String, dynamic> json) {
    final warehouse = asMap(json['warehouse']);
    return Location(
      id: asString(json['id']),
      warehouseId:
          asStringOrNull(json['warehouseId']) ?? asString(warehouse['id']),
      code: asString(json['code']),
      name: asStringOrNull(json['name']),
      active: asBool(json['active'], fallback: true),
      warehouseName: asStringOrNull(warehouse['name']) ??
          asStringOrNull(json['warehouseName']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'warehouseId': warehouseId,
        'code': code,
        'name': name,
        'active': active,
      };
}
