import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../core/json_utils.dart';
import '../core/l10n.dart';
import '../core/session.dart';
import '../models/product.dart';

/// The price a supplier last charged for a product.
class LastSupplierPrice {
  const LastSupplierPrice({
    required this.unitPrice,
    required this.orderNumber,
    this.orderDate,
  });

  final double unitPrice;
  final String orderNumber;
  final DateTime? orderDate;

  factory LastSupplierPrice.fromJson(Map<String, dynamic> json) =>
      LastSupplierPrice(
        unitPrice: asDouble(json['unitPrice']),
        orderNumber: asString(json['orderNumber']),
        orderDate: asDate(json['orderDate']),
      );
}

/// Loads the last received purchase price for [supplierId] and [productId].
Future<LastSupplierPrice?> fetchLastSupplierPrice(
  ApiClient api, {
  required String supplierId,
  required String productId,
}) async {
  final json = await api.get(
    '/purchase-orders/last-price',
    query: <String, dynamic>{
      'supplierId': supplierId,
      'productId': productId,
    },
  );
  final data = asMap(json)['data'];
  if (data is! Map) return null;
  return LastSupplierPrice.fromJson(asMap(data));
}

/// Loads and shows what [supplierId] last charged for [product].
class LastSupplierPriceLoader extends StatefulWidget {
  const LastSupplierPriceLoader({
    super.key,
    required this.supplierId,
    required this.product,
  });

  final String supplierId;
  final Product? product;

  @override
  State<LastSupplierPriceLoader> createState() =>
      _LastSupplierPriceLoaderState();
}

class _LastSupplierPriceLoaderState extends State<LastSupplierPriceLoader> {
  LastSupplierPrice? _price;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LastSupplierPriceLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product?.id != widget.product?.id ||
        oldWidget.supplierId != widget.supplierId) {
      setState(() => _price = null);
      _load();
    }
  }

  Future<void> _load() async {
    final product = widget.product;
    if (product == null) return;
    final key = '${widget.supplierId}|${product.id}';
    try {
      final last = await fetchLastSupplierPrice(
        context.read<Session>().api,
        supplierId: widget.supplierId,
        productId: product.id,
      );
      if (!mounted || last == null) return;
      if ('${widget.supplierId}|${widget.product?.id}' != key) return;
      setState(() => _price = last);
    } on ApiException {
      // The history hint is optional.
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = _price;
    if (price == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.history_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${s.lastPurchasePrice}: '
              '${Formatters.money(price.unitPrice)} · ${price.orderNumber}'
              '${price.orderDate == null ? '' : ' · ${Formatters.date(price.orderDate)}'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the product's last purchase price while writing an invoice / order.
///
/// This is a screen-only hint for whoever is entering the document — it is
/// never sent to the printed invoice. `product.costPrice` holds the last price
/// the item was purchased at (it is refreshed every time a purchase is
/// received).
class LastPurchasePriceHint extends StatelessWidget {
  const LastPurchasePriceHint({super.key, required this.product});

  final Product? product;

  @override
  Widget build(BuildContext context) {
    final value = product;
    if (value == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.history_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${s.lastPurchasePrice}: '
              '${Formatters.money(value.costPrice, currencyCode: value.currencyCode)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
