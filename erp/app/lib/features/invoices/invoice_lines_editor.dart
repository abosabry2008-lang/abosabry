import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/invoice.dart';
import '../../models/product.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/last_sale_price.dart';
import '../../widgets/stock_on_hand_hint.dart';
import '../inventory/product_picker_field.dart';

/// Mutable invoice line used by the invoice editor.
class InvoiceLineDraft {
  InvoiceLineDraft({
    this.productId,
    String description = '',
    double quantity = 1,
    double price = 0,
    double discount = 0,
    double taxRate = 0,
  })  : descriptionController = TextEditingController(text: description),
        quantityController = TextEditingController(text: format(quantity)),
        priceController = TextEditingController(text: format(price)),
        discountController = TextEditingController(text: format(discount)),
        taxController = TextEditingController(text: format(taxRate));

  Product? product;
  String? productId;
  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController priceController;
  final TextEditingController discountController;
  final TextEditingController taxController;

  static String format(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  factory InvoiceLineDraft.fromLine(InvoiceLine line) => InvoiceLineDraft(
        productId: line.productId,
        description: line.description,
        quantity: line.quantity.toDouble(),
        price: line.unitPrice,
        discount: line.discount,
        taxRate: line.taxRate,
      );

  int get quantity =>
      double.tryParse(quantityController.text.trim())?.round() ?? 0;

  double get price => double.tryParse(priceController.text.trim()) ?? 0;

  double get discount => double.tryParse(discountController.text.trim()) ?? 0;

  double get taxRate => double.tryParse(taxController.text.trim()) ?? 0;

  double get gross => quantity * price;

  double get net => (gross - discount).clamp(0.0, double.infinity).toDouble();

  double get taxAmount => net * taxRate / 100;

  double get lineTotal => net + taxAmount;

  bool get isValid =>
      quantity > 0 &&
      (product != null || descriptionController.text.trim().isNotEmpty);

  void setProduct(Product value) {
    product = value;
    productId = value.id;
    if (descriptionController.text.trim().isEmpty) {
      descriptionController.text = value.name;
    }
    if (price == 0) {
      priceController.text = format(value.salePrice);
    }
  }

  Map<String, dynamic> toJson() {
    final description = descriptionController.text.trim();
    return <String, dynamic>{
      'productId': product?.id ?? productId,
      'description': description.isEmpty ? (product?.name ?? '') : description,
      'quantity': quantity,
      'unitPrice': price,
      'discount': discount,
      'taxRate': taxRate,
    };
  }

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    priceController.dispose();
    discountController.dispose();
    taxController.dispose();
  }
}

/// Invoice lines as a compact sheet: a quick-add bar on top, then one row per
/// item with its quantity, price and total. Picking an item adds it at once and
/// shows what this customer paid for it last time.
class InvoiceLinesEditor extends StatefulWidget {
  const InvoiceLinesEditor({
    super.key,
    required this.lines,
    required this.onChanged,
    this.customerId,
    this.enabled = true,
  });

  final List<InvoiceLineDraft> lines;
  final VoidCallback onChanged;
  final String? customerId;
  final bool enabled;

  @override
  State<InvoiceLinesEditor> createState() => _InvoiceLinesEditorState();
}

class _InvoiceLinesEditorState extends State<InvoiceLinesEditor> {
  /// The product currently staged in the quick-add bar.
  Product? _quickProduct;
  LastSalePrice? _lastPrice;
  final TextEditingController _quickQty = TextEditingController(text: '1');
  final TextEditingController _quickPrice = TextEditingController();
  final FocusNode _qtyFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();

  List<InvoiceLineDraft> get lines => widget.lines;
  bool get enabled => widget.enabled;

  @override
  void dispose() {
    _quickQty.dispose();
    _quickPrice.dispose();
    _qtyFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  /// Stages a product and pre-fills the price with what this customer paid last
  /// time, falling back to the list price when there is no history.
  Future<void> _stageProduct(Product product) async {
    setState(() {
      _quickProduct = product;
      _lastPrice = null;
      _quickPrice.text = InvoiceLineDraft.format(product.salePrice);
    });
    _qtyFocus.requestFocus();

    final customerId = widget.customerId;
    if (customerId == null) return;
    try {
      final last = await fetchLastSalePrice(
        context.read<Session>().api,
        customerId: customerId,
        productId: product.id,
      );
      if (!mounted || last == null || _quickProduct?.id != product.id) return;
      setState(() {
        _lastPrice = last;
        _quickPrice.text = InvoiceLineDraft.format(last.unitPrice);
      });
    } on ApiException {
      // The history hint is optional; the list price stays in place.
    }
  }

  /// Adds the staged product as a line and clears the bar for the next one.
  void _addQuickLine() {
    final product = _quickProduct;
    if (product == null) return;
    final quantity = double.tryParse(_quickQty.text.trim())?.round() ?? 0;
    if (quantity <= 0) return;
    final price = double.tryParse(_quickPrice.text.trim()) ?? product.salePrice;
    final line = InvoiceLineDraft(
      productId: product.id,
      quantity: quantity.toDouble(),
      price: price,
      taxRate: product.taxRate,
    )..setProduct(product);
    setState(() {
      lines.add(line);
      _quickProduct = null;
      _lastPrice = null;
      _quickQty.text = '1';
      _quickPrice.clear();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final subtotal = lines.fold<double>(0, (sum, line) => sum + line.gross);
    final discountTotal = lines.fold<double>(0, (sum, line) => sum + line.discount);
    final taxTotal = lines.fold<double>(0, (sum, line) => sum + line.taxAmount);
    final total = lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ProductPickerField(
                product: _quickProduct,
                enabled: enabled,
                onChanged: _stageProduct,
              ),
              if (_lastPrice != null) LastSalePriceHint(price: _lastPrice!),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppNumberField(
                      label: s.qty,
                      controller: _quickQty,
                      focusNode: _qtyFocus,
                      enabled: enabled,
                      decimal: false,
                      onSubmitted: (_) => _priceFocus.requestFocus(),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: AppNumberField(
                      label: s.unitPrice,
                      controller: _quickPrice,
                      focusNode: _priceFocus,
                      enabled: enabled,
                      onSubmitted: (_) => _addQuickLine(),
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: enabled && _quickProduct != null
                        ? _addQuickLine
                        : null,
                    icon: const Icon(Icons.add),
                    label: Text(s.addLine),
                  ),
                ],
              ),
            ],
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
              child: _CompactInvoiceLine(
                key: ObjectKey(lines[index]),
                line: lines[index],
                enabled: enabled,
                onChanged: widget.onChanged,
                onRemove: () {
                  lines.removeAt(index).dispose();
                  widget.onChanged();
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
              _SummaryRow(label: s.discountWord, value: -discountTotal),
              _SummaryRow(label: s.tax, value: taxTotal),
              const Divider(),
              _SummaryRow(label: s.total, value: total, emphasise: true),
            ],
          ),
        ),
      ],
    );
  }
}

/// One invoice line: item, quantity, price and total on a single row. Discount,
/// tax, description and product change are behind the edit button.
class _CompactInvoiceLine extends StatefulWidget {
  const _CompactInvoiceLine({
    super.key,
    required this.line,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final InvoiceLineDraft line;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_CompactInvoiceLine> createState() => _CompactInvoiceLineState();
}

class _CompactInvoiceLineState extends State<_CompactInvoiceLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final line = widget.line;
    final title = line.product?.name ??
        (line.descriptionController.text.trim().isEmpty
            ? s.item
            : line.descriptionController.text.trim());

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Text(
                  Formatters.money(line.lineTotal),
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  tooltip: s.edit,
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.enabled
                      ? () => setState(() => _expanded = !_expanded)
                      : null,
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.tune_outlined,
                  ),
                ),
                IconButton(
                  tooltip: s.removeLine,
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.enabled ? widget.onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppNumberField(
                    label: s.qty,
                    controller: line.quantityController,
                    enabled: widget.enabled,
                    decimal: false,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: AppNumberField(
                    label: s.unitPrice,
                    controller: line.priceController,
                    enabled: widget.enabled,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
              ],
            ),
            if (_expanded) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppNumberField(
                      label: s.discountWord,
                      controller: line.discountController,
                      enabled: widget.enabled,
                      onChanged: (_) => widget.onChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppNumberField(
                      label: s.taxRatePercent,
                      controller: line.taxController,
                      enabled: widget.enabled,
                      onChanged: (_) => widget.onChanged(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ProductPickerField(
                product: line.product,
                enabled: widget.enabled,
                fallbackLabel: line.descriptionController.text.trim().isEmpty
                    ? null
                    : line.descriptionController.text.trim(),
                onChanged: (value) {
                  line.setProduct(value);
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: s.description,
                controller: line.descriptionController,
                enabled: widget.enabled,
                prefixIcon: Icons.notes_outlined,
                onChanged: (_) => widget.onChanged(),
              ),
              StockOnHandHint(
                product: line.product,
                requestedQuantity: line.quantity,
              ),
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
