import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/product.dart';

/// Shows how many units of the product are on hand while writing a document.
///
/// Screen-only hint for whoever is entering the invoice / order (it warns when
/// the quantity being sold is more than what is available). It is never sent to
/// the printed document.
class StockOnHandHint extends StatelessWidget {
  const StockOnHandHint({
    super.key,
    required this.product,
    this.requestedQuantity,
  });

  final Product? product;

  /// Quantity currently entered on the line, used to flag a shortage.
  final int? requestedQuantity;

  @override
  Widget build(BuildContext context) {
    final value = product;
    if (value == null || value.quantityOnHand == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final s = context.s;
    final onHand = value.quantityOnHand!;
    final short =
        requestedQuantity != null && requestedQuantity! > onHand;
    final bpc = value.boxesPerCarton;
    final stockText = bpc > 0
        ? s.packStock(onHand ~/ bpc, onHand % bpc)
        : '$onHand ${value.unit}';

    final color = short ? theme.colorScheme.error : theme.colorScheme.primary;
    final label = short
        ? '${s.shortageQty}: $stockText'
        : '${s.onHand}: $stockText';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Icon(
            short ? Icons.warning_amber_outlined : Icons.inventory_2_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
