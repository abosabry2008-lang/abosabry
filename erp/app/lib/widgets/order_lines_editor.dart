import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../core/l10n.dart';
import '../core/session.dart';
import '../features/inventory/product_picker_field.dart';
import '../models/product.dart';
import 'form_fields.dart';
import 'last_purchase_price_hint.dart';
import 'last_sale_price.dart';
import 'stock_on_hand_hint.dart';

/// Editable order line used by the purchase and sales order forms.
class OrderLineDraft {
  OrderLineDraft({
    this.product,
    double quantity = 1,
    double price = 0,
    double discount = 0,
    double taxRate = 0,
    this.sellUnit = 'unit',
  })  : quantityController = TextEditingController(text: _format(quantity)),
        priceController = TextEditingController(text: _format(price)),
        discountController = TextEditingController(text: _format(discount)),
        taxController = TextEditingController(text: _format(taxRate));

  Product? product;
  String sellUnit; // unit | box | carton
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

  bool get hasPackaging => (product?.boxesPerCarton ?? 0) > 0;

  double get gross => quantity * price;

  double get net => (gross - discount).clamp(0.0, double.infinity).toDouble();

  double get taxAmount => net * taxRate / 100;

  double get lineTotal => net + taxAmount;

  /// Pre-tax revenue and cost for this line (admin-only profit view).
  double get revenue => net;

  double get cost => quantity * (product?.costPrice ?? 0);

  double get profit => revenue - cost;

  bool get isValid => product != null && product!.id.isNotEmpty && quantity > 0;

  /// True when a priced line sells below the product's recorded cost.
  bool get priceBelowCost =>
      product != null && price > 0 && price < product!.costPrice;

  void applyPackPrice({bool preferSalePrice = true}) {
    final p = product;
    if (p == null) return;
    final bpc = p.boxesPerCarton;
    if (bpc <= 0) {
      sellUnit = 'unit';
      if (price == 0) {
        final suggested = preferSalePrice
            ? (p.salePrice > 0 ? p.salePrice : (p.costPrice > 0 ? p.costPrice : 0.0))
            : (p.costPrice > 0 ? p.costPrice : (p.salePrice > 0 ? p.salePrice : 0.0));
        priceController.text = _format(suggested.toDouble());
      }
      if (taxRate == 0 && p.taxRate > 0) {
        taxController.text = _format(p.taxRate);
      }
      return;
    }
    if (sellUnit == 'box') {
      if (preferSalePrice) {
        if (p.boxPrice != null && p.boxPrice! > 0) {
          priceController.text = _format(p.boxPrice!);
        } else if (p.cartonPrice != null && p.cartonPrice! > 0 && bpc > 0) {
          priceController.text = _format((p.cartonPrice! / bpc).toDouble());
        } else if (p.salePrice > 0 && bpc > 0) {
          priceController.text = _format((p.salePrice * bpc).toDouble());
        } else if (p.costPrice > 0) {
          priceController.text = _format(p.costPrice);
        } else {
          priceController.text = _format(((p.salePrice / bpc)).clamp(0, double.infinity).toDouble());
        }
      } else {
        if (p.costPrice > 0) {
          priceController.text = _format(p.costPrice);
        } else if (p.boxPrice != null && p.boxPrice! > 0) {
          priceController.text = _format(p.boxPrice!);
        } else if (p.cartonPrice != null && p.cartonPrice! > 0 && bpc > 0) {
          priceController.text = _format((p.cartonPrice! / bpc).toDouble());
        } else {
          priceController.text = _format(((p.salePrice / bpc)).clamp(0, double.infinity).toDouble());
        }
      }
    } else if (sellUnit == 'carton') {
      if (preferSalePrice) {
        if (p.cartonPrice != null && p.cartonPrice! > 0) {
          priceController.text = _format(p.cartonPrice!);
        } else if (p.salePrice > 0 && bpc > 0) {
          priceController.text = _format((p.salePrice * bpc).toDouble());
        } else if (p.costPrice > 0 && bpc > 0) {
          priceController.text = _format((p.costPrice * bpc).toDouble());
        } else {
          priceController.text = _format(((p.boxPrice ?? p.salePrice) * bpc).toDouble());
        }
      } else {
        if (p.costPrice > 0 && bpc > 0) {
          priceController.text = _format((p.costPrice * bpc).toDouble());
        } else if (p.cartonPrice != null && p.cartonPrice! > 0) {
          priceController.text = _format(p.cartonPrice!);
        } else {
          priceController.text = _format(((p.boxPrice ?? p.salePrice) * bpc).toDouble());
        }
      }
    } else {
      sellUnit = 'box';
      if (preferSalePrice) {
        if (p.boxPrice != null && p.boxPrice! > 0) {
          priceController.text = _format(p.boxPrice!);
        } else if (p.cartonPrice != null && p.cartonPrice! > 0 && bpc > 0) {
          priceController.text = _format((p.cartonPrice! / bpc).toDouble());
        } else if (p.salePrice > 0 && bpc > 0) {
          priceController.text = _format((p.salePrice * bpc).toDouble());
        } else if (p.costPrice > 0) {
          priceController.text = _format(p.costPrice);
        } else {
          priceController.text = _format(((p.salePrice / bpc)).clamp(0, double.infinity).toDouble());
        }
      } else {
        if (p.costPrice > 0) {
          priceController.text = _format(p.costPrice);
        } else if (p.boxPrice != null && p.boxPrice! > 0) {
          priceController.text = _format(p.boxPrice!);
        } else if (p.cartonPrice != null && p.cartonPrice! > 0 && bpc > 0) {
          priceController.text = _format((p.cartonPrice! / bpc).toDouble());
        } else {
          priceController.text = _format(((p.salePrice / bpc)).clamp(0, double.infinity).toDouble());
        }
      }
    }
    if (taxRate == 0 && p.taxRate > 0) {
      taxController.text = _format(p.taxRate);
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': product?.id,
        'quantity': quantity,
        'unitPrice': price,
        'unitCost': price,
        'discount': discount,
        'taxRate': taxRate,
        if (sellUnit != 'unit') 'sellUnit': sellUnit,
      };

  void setProduct(Product value, {bool preferSalePrice = false}) {
    product = value;
    final bpc = value.boxesPerCarton;
    if (bpc > 0 && sellUnit == 'unit') {
      sellUnit = 'box';
    } else if (bpc <= 0) {
      sellUnit = 'unit';
    }
    if (price == 0) {
      if (bpc > 0) {
        applyPackPrice(preferSalePrice: preferSalePrice);
        return;
      }
      final suggested = preferSalePrice
          ? (value.salePrice > 0 ? value.salePrice : (value.costPrice > 0 ? value.costPrice : 0.0))
          : (value.costPrice > 0 ? value.costPrice : (value.salePrice > 0 ? value.salePrice : 0.0));
      priceController.text = _format(suggested.toDouble());
    }
    if (taxRate == 0 && value.taxRate > 0) {
      taxController.text = _format(value.taxRate);
    }
  }

  void dispose() {
    quantityController.dispose();
    priceController.dispose();
    discountController.dispose();
    taxController.dispose();
  }
}

/// Order lines as a compact sheet. Picking an item adds it at once; each row
/// shows the item, quantity, price and total, with discount and tax behind the
/// edit button.
class OrderLinesEditor extends StatelessWidget {
  const OrderLinesEditor({
    super.key,
    required this.lines,
    required this.onChanged,
    this.showDiscount = false,
    this.showTax = true,
    this.enabled = true,
    this.priceLabel,
    this.preferSalePrice = false,
    this.enforceSalePriceFloor = false,
    this.customerId,
    this.supplierId,
    this.showProfit = false,
  });

  final List<OrderLineDraft> lines;
  final VoidCallback onChanged;
  final bool showDiscount;
  final bool showTax;
  final bool enabled;
  final String? priceLabel;

  /// When true, picking a product auto-fills its sale price (sales / returns
  /// documents); when false the cost price is used (purchases).
  final bool preferSalePrice;

  /// When true, any priced line below the product's cost is highlighted with
  /// an error message (sales must not sell below cost).
  final bool enforceSalePriceFloor;

  /// Customer of a sales document. When set, each item shows what this
  /// customer last paid and the price starts at that amount.
  final String? customerId;

  /// Supplier of a purchase/return document. When set, each item shows the
  /// price this supplier last charged and starts at that amount.
  final String? supplierId;

  /// Admin-only: show revenue, cost and profit for the document being entered.
  final bool showProfit;

  double get subtotal =>
      lines.fold<double>(0, (sum, line) => sum + line.gross);

  double get discountTotal =>
      lines.fold<double>(0, (sum, line) => sum + line.discount);

  double get taxTotal =>
      lines.fold<double>(0, (sum, line) => sum + line.taxAmount);

  double get total => lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  double get revenue => lines.fold<double>(0, (sum, line) => sum + line.revenue);

  double get cost => lines.fold<double>(0, (sum, line) => sum + line.cost);

  double get profit => revenue - cost;

  void _addProduct(BuildContext context, Product product) {
    final line = OrderLineDraft()..setProduct(product, preferSalePrice: preferSalePrice);
    // Newest line first so the item just added is immediately visible at the top.
    lines.insert(0, line);
    onChanged();
    _prefillLastPrice(context, line, product);
  }

  /// Starts the line at the price this customer paid or this supplier charged
  /// last time, when known.
  Future<void> _prefillLastPrice(
    BuildContext context,
    OrderLineDraft line,
    Product product,
  ) async {
    final customer = customerId;
    final supplier = supplierId;
    try {
      if (customer != null) {
        final last = await fetchLastSalePrice(
          context.read<Session>().api,
          customerId: customer,
          productId: product.id,
        );
        if (!context.mounted || last == null) return;
        if (!lines.contains(line) || line.product?.id != product.id) return;
        line.priceController.text = OrderLineDraft._format(last.unitPrice);
        onChanged();
      } else if (supplier != null) {
        final last = await fetchLastSupplierPrice(
          context.read<Session>().api,
          supplierId: supplier,
          productId: product.id,
        );
        if (!context.mounted || last == null) return;
        if (!lines.contains(line) || line.product?.id != product.id) return;
        line.priceController.text = OrderLineDraft._format(last.unitPrice);
        onChanged();
      }
    } on ApiException {
      // The history is optional; the list price stays in place.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ProductPickerField(
            product: null,
            enabled: enabled,
            label: s.addLine,
            onChanged: (product) => _addProduct(context, product),
          ),
        ),
        const SizedBox(height: 12),
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              s.noLinesYet,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          for (var index = 0; index < lines.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OrderLineRow(
                key: ObjectKey(lines[index]),
                line: lines[index],
                enabled: enabled,
                priceLabel: priceLabel,
                preferSalePrice: preferSalePrice,
                showDiscount: showDiscount,
                showTax: showTax,
                enforceSalePriceFloor: enforceSalePriceFloor,
                customerId: customerId,
                supplierId: supplierId,
                onProductPicked: (product, target) =>
                    _prefillLastPrice(context, target, product),
                onChanged: onChanged,
                onRemove: () {
                  lines.removeAt(index).dispose();
                  onChanged();
                },
              ),
            ),
        const SizedBox(height: 8),
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
        if (showProfit) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: <Widget>[
                _SummaryRow(label: s.netSales, value: revenue),
                _SummaryRow(label: s.costOfSales, value: cost),
                const Divider(),
                _SummaryRow(label: s.netProfit, value: profit, emphasise: true),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One order line: item, quantity, price and total on a single row.
class _OrderLineRow extends StatefulWidget {
  const _OrderLineRow({
    super.key,
    required this.line,
    required this.enabled,
    required this.priceLabel,
    required this.preferSalePrice,
    required this.showDiscount,
    required this.showTax,
    required this.enforceSalePriceFloor,
    this.customerId,
    this.supplierId,
    this.onProductPicked,
    required this.onChanged,
    required this.onRemove,
  });

  final OrderLineDraft line;
  final bool enabled;
  final String? priceLabel;
  final bool preferSalePrice;
  final bool showDiscount;
  final bool showTax;
  final bool enforceSalePriceFloor;
  final String? customerId;
  final String? supplierId;
  final void Function(Product product, OrderLineDraft line)? onProductPicked;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_OrderLineRow> createState() => _OrderLineRowState();
}

class _OrderLineRowState extends State<_OrderLineRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.s;
    final line = widget.line;
    final product = line.product;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 2, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: product == null
                      ? ProductPickerField(
                          product: null,
                          enabled: widget.enabled,
                          onChanged: (value) {
                            line.setProduct(value, preferSalePrice: widget.preferSalePrice);
                            widget.onChanged();
                            widget.onProductPicked?.call(value, line);
                          },
                        )
                      : Text(
                          '${product.name} (${product.sku})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                ),
                Text(
                  Formatters.money(line.lineTotal),
                  style: theme.textTheme.titleSmall,
                ),
                IconButton(
                  tooltip: s.edit,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: widget.enabled
                      ? () => setState(() => _expanded = !_expanded)
                      : null,
                  icon: Icon(_expanded ? Icons.expand_less : Icons.tune_outlined),
                ),
                IconButton(
                  tooltip: s.removeLine,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: widget.enabled ? widget.onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                if (line.hasPackaging) ...<Widget>[
                  SizedBox(
                    width: 96,
                    child: DropdownButtonFormField<String>(
                      value: line.sellUnit == 'carton' ? 'carton' : 'box',
                      decoration: const InputDecoration(
                        labelText: null,
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'box', child: Text('علبة')),
                        DropdownMenuItem(value: 'carton', child: Text('كرتونة')),
                      ],
                      onChanged: widget.enabled
                          ? (value) {
                              if (value == null) return;
                              line.sellUnit = value;
                              line.applyPackPrice(preferSalePrice: widget.preferSalePrice);
                              widget.onChanged();
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: AppNumberField(
                    label: s.qty,
                    controller: line.quantityController,
                    enabled: widget.enabled,
                    decimal: false,
                    dense: true,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: AppNumberField(
                    label: widget.priceLabel ?? s.unitPrice,
                    controller: line.priceController,
                    enabled: widget.enabled,
                    dense: true,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
              ],
            ),
            if (product != null) ...<Widget>[
              if (widget.customerId != null)
                LastSalePriceLoader(
                  customerId: widget.customerId!,
                  product: product,
                )
              else if (widget.supplierId != null)
                LastSupplierPriceLoader(
                  supplierId: widget.supplierId!,
                  product: product,
                ),
              StockOnHandHint(
                product: product,
                requestedQuantity: line.quantity,
              ),
            ],
            if (widget.enforceSalePriceFloor && line.priceBelowCost)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  s.priceBelowCost(product?.name ?? s.product),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (_expanded) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  if (widget.showDiscount) ...<Widget>[
                    Expanded(
                      child: AppNumberField(
                        label: s.discountWord,
                        controller: line.discountController,
                        enabled: widget.enabled,
                        dense: true,
                        onChanged: (_) => widget.onChanged(),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (widget.showTax)
                    Expanded(
                      child: AppNumberField(
                        label: s.taxRatePercent,
                        controller: line.taxController,
                        enabled: widget.enabled,
                        dense: true,
                        onChanged: (_) => widget.onChanged(),
                      ),
                    ),
                ],
              ),
              if (widget.customerId == null && widget.supplierId == null)
                LastPurchasePriceHint(product: product),
            ],
          ],
        ),
      ),
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
