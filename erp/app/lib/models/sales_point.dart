import '../core/json_utils.dart';

/// A single data point in a report series (sales by period, top products, ...).
class SalesPoint {
  const SalesPoint({
    required this.label,
    this.value = 0,
    this.quantity = 0,
    this.count = 0,
    this.productId,
    this.sku,
  });

  final String label;
  final double value;
  final int quantity;
  final int count;
  final String? productId;
  final String? sku;

  factory SalesPoint.fromJson(Map<String, dynamic> json) {
    final period = json['period'] ?? json['label'] ?? json['date'] ??
        json['name'] ?? json['productName'] ?? json['key'];
    return SalesPoint(
      label: asString(period, fallback: '—'),
      value: asDouble(
        json['value'] ??
            json['total'] ??
            json['amount'] ??
            json['totalSales'] ??
            json['revenue'] ??
            json['balance'],
      ),
      quantity: asInt(
        json['quantity'] ??
            json['qty'] ??
            json['totalQuantity'] ??
            json['quantitySold'] ??
            json['sold'],
      ),
      count: asInt(json['count'] ?? json['orders'] ?? json['invoiceCount']),
      productId: asStringOrNull(json['productId']) ??
          asStringOrNull(asMap(json['product'])['id']),
      sku: asStringOrNull(json['sku']) ??
          asStringOrNull(asMap(json['product'])['sku']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'value': value,
        'quantity': quantity,
        'count': count,
      };
}
