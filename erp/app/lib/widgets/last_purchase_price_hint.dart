import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/l10n.dart';
import '../models/product.dart';

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
