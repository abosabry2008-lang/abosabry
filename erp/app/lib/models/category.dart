import '../core/json_utils.dart';

/// A product category.
class Category {
  const Category({
    required this.id,
    required this.name,
    this.description,
    this.productCount = 0,
  });

  final String id;
  final String name;
  final String? description;
  final int productCount;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: asString(json['id']),
        name: asString(json['name']),
        description: asStringOrNull(json['description']),
        productCount: asInt(
          json['productCount'] ?? asMap(json['_count'])['products'],
        ),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
      };
}
