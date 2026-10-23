import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/json_utils.dart';
import '../core/l10n.dart';

/// The price a customer was last invoiced for a product.
class LastSalePrice {
  const LastSalePrice({
    required this.unitPrice,
    required this.sellUnit,
    required this.invoiceNumber,
    this.issueDate,
  });

  final double unitPrice;
  final String sellUnit;
  final String invoiceNumber;
  final DateTime? issueDate;

  factory LastSalePrice.fromJson(Map<String, dynamic> json) => LastSalePrice(
        unitPrice: asDouble(json['unitPrice']),
        sellUnit: asString(json['sellUnit'], fallback: 'unit'),
        invoiceNumber: asString(json['invoiceNumber']),
        issueDate: asDate(json['issueDate']),
      );
}

/// Loads the last invoiced price for [customerId] and [productId]; null when the
/// customer never bought the product.
Future<LastSalePrice?> fetchLastSalePrice(
  ApiClient api, {
  required String customerId,
  required String productId,
}) async {
  final json = await api.get(
    '/invoices/last-price',
    query: <String, dynamic>{'customerId': customerId, 'productId': productId},
  );
  final data = asMap(json)['data'];
  if (data is! Map) return null;
  return LastSalePrice.fromJson(asMap(data));
}

/// Screen-only hint: the price this customer paid last time for the product.
class LastSalePriceHint extends StatelessWidget {
  const LastSalePriceHint({super.key, required this.price});

  final LastSalePrice price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.s;
    final unit = price.sellUnit == 'unit' ? '' : ' / ${price.sellUnit}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Icon(Icons.sell_outlined, size: 16, color: theme.colorScheme.tertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${s.lastSalePriceToCustomer}: '
              '${Formatters.money(price.unitPrice)}$unit · ${price.invoiceNumber}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
