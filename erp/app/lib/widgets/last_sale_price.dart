import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../core/json_utils.dart';
import '../core/l10n.dart';
import '../core/session.dart';
import '../models/product.dart';

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

/// Loads and shows the last sale price for [product] to [customerId]. Renders
/// nothing when there is no product or no earlier sale.
class LastSalePriceLoader extends StatefulWidget {
  const LastSalePriceLoader({
    super.key,
    required this.customerId,
    required this.product,
  });

  final String customerId;
  final Product? product;

  @override
  State<LastSalePriceLoader> createState() => _LastSalePriceLoaderState();
}

class _LastSalePriceLoaderState extends State<LastSalePriceLoader> {
  LastSalePrice? _price;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LastSalePriceLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product?.id != widget.product?.id ||
        oldWidget.customerId != widget.customerId) {
      setState(() => _price = null);
      _load();
    }
  }

  Future<void> _load() async {
    final product = widget.product;
    if (product == null) return;
    final key = '${widget.customerId}|${product.id}';
    try {
      final last = await fetchLastSalePrice(
        context.read<Session>().api,
        customerId: widget.customerId,
        productId: product.id,
      );
      if (!mounted || last == null) return;
      if ('${widget.customerId}|${widget.product?.id}' != key) return;
      setState(() => _price = last);
    } on ApiException {
      // The history hint is optional.
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = _price;
    if (price == null) return const SizedBox.shrink();
    return LastSalePriceHint(price: price);
  }
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
              '${Formatters.money(price.unitPrice)}$unit · ${price.invoiceNumber}'
              '${price.issueDate == null ? '' : ' · ${Formatters.date(price.issueDate)}'}',
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
