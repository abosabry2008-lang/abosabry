import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/l10n.dart';
import '../features/inventory/product_picker_field.dart';
import '../models/product.dart';
import 'form_fields.dart';

/// Editable order line used by the purchase and sales order forms.
class OrderLineDraft {
  OrderLineDraft({
    this.product,
    double quantity = 1,
    double price = 0,
    double discount = 0,
    double taxRate = 0,
  })  : quantityController = TextEditingController(text: _format(quantity)),
        priceController = TextEditingController(text: _format(price)),
        discountController = TextEditingController(text: _format(discount)),
        taxController = TextEditingController(text: _format(taxRate));

  Product? product;
  final TextEditingController quantityController;
  final TextEditingController priceController;
  final TextEditingController discountController;
  final TextEditingController taxController;

  static String _format(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  int get quantity => double.tryParse(quantityController.text.trim())?.round() ?? 0;

  double get price => double.tryParse(priceController.text.trim()) ?? 0;

  double get discount => double.tryParse(discountController.text.trim()) ?? 0;

  double get taxRate => double.tryParse(taxController.text.trim()) ?? 0;

  double get gross => quantity * price;

  double get net => (gross - discount).clamp(0.0, double.infinity).toDouble();

  double get taxAmount => net * taxRate / 100;

  double get lineTotal => net + taxAmount;

  bool get isValid => product != null && product!.id.isNotEmpty && quantity > 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': product?.id,
        'quantity': quantity,
        'unitPrice': price,
        'unitCost': price,
        'discount': discount,
        'taxRate': taxRate,
      };

  void setProduct(Product value, {bool autoFillPrice = true}) {
    product = value;
    if (autoFillPrice && price == 0) {
      priceController.text = _format(value.costPrice > 0 ? value.costPrice : value.salePrice);
    }
  }

  void dispose() {
    quantityController.dispose();
    priceController.dispose();
    discountController.dispose();
    taxController.dispose();
  }
}

/// Renders an editable list of [OrderLineDraft]s with a totals footer.
class OrderLinesEditor extends StatelessWidget {
  const OrderLinesEditor({
    super.key,
    required this.lines,
    required this.onChanged,
    this.showDiscount = false,
    this.showTax = true,
    this.enabled = true,
    this.priceLabel,
  });

  final List<OrderLineDraft> lines;
  final VoidCallback onChanged;
  final bool showDiscount;
  final bool showTax;
  final bool enabled;
  final String? priceLabel;

  double get subtotal =>
      lines.fold<double>(0, (sum, line) => sum + line.gross);

  double get discountTotal =>
      lines.fold<double>(0, (sum, line) => sum + line.discount);

  double get taxTotal =>
      lines.fold<double>(0, (sum, line) => sum + line.taxAmount);

  double get total => lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < lines.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: ProductPickerField(
                            product: lines[index].product,
                            enabled: enabled,
                            onChanged: (value) {
                              lines[index].setProduct(value);
                              onChanged();
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: s.removeLine,
                          onPressed: enabled
                              ? () {
                                  lines.removeAt(index).dispose();
                                  onChanged();
                                }
                              : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppNumberField(
                            label: s.qty,
                            controller: lines[index].quantityController,
                            enabled: enabled,
                            decimal: false,
                            onChanged: (_) => onChanged(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: AppNumberField(
                            label: priceLabel ?? s.unitPrice,
                            controller: lines[index].priceController,
                            enabled: enabled,
                            onChanged: (_) => onChanged(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        if (showDiscount) ...<Widget>[
                          Expanded(
                            child: AppNumberField(
                              label: s.discountWord,
                              controller: lines[index].discountController,
                              enabled: enabled,
                              onChanged: (_) => onChanged(),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (showTax)
                          Expanded(
                            child: AppNumberField(
                              label: s.taxRatePercent,
                              controller: lines[index].taxController,
                              enabled: enabled,
                              onChanged: (_) => onChanged(),
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                s.lineTotal,
                                style: theme.textTheme.labelSmall,
                              ),
                              Text(
                                Formatters.money(lines[index].lineTotal),
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: enabled
              ? () {
                  lines.add(OrderLineDraft());
                  onChanged();
                }
              : null,
          icon: const Icon(Icons.add),
          label: Text(s.addLine),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              _SummaryRow(label: s.subtotal, value: subtotal),
              if (showDiscount)
                _SummaryRow(label: s.discountWord, value: -discountTotal),
              if (showTax) _SummaryRow(label: s.tax, value: taxTotal),
              const Divider(),
              _SummaryRow(
                label: s.total,
                value: total,
                emphasise: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final double value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasise
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(
            Formatters.money(value),
            style: style?.copyWith(
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
