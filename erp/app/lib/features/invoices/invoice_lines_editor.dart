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
    this.costSnapshot,
    this.sellUnit = 'unit',
  })  : descriptionController = TextEditingController(text: description),
        quantityController = TextEditingController(text: format(quantity)),
        priceController = TextEditingController(text: format(price)),
        discountController = TextEditingController(text: format(discount)),
        taxController = TextEditingController(text: format(taxRate));

  Product? product;
  String? productId;
  /// Cost at the time the invoice was written (per base box).
  double? costSnapshot;
  /// unit | box | carton — the unit the operator is entering quantities in.
  String sellUnit;
  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController priceController;
  final TextEditingController discountController;
  final TextEditingController taxController;

  int get boxesPerCarton => product?.boxesPerCarton ?? 0;

  /// How many base boxes one entered unit represents.
  double get unitFactor =>
      sellUnit == 'carton' && boxesPerCarton > 0 ? boxesPerCarton.toDouble() : 1;

  /// Entered quantity converted to the stored base unit (boxes).
  int get baseQuantity => (quantity * unitFactor).round();

  double get baseUnitPrice => price / unitFactor;

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
        costSnapshot: line.unitCost,
        sellUnit: line.sellUnit,
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

  double get revenue => net;

  double get cost =>
      baseQuantity * (costSnapshot ?? product?.costPrice ?? 0);

  double get profit => revenue - cost;

  bool get isValid =>
      quantity > 0 &&
      (product != null || descriptionController.text.trim().isNotEmpty);

  /// Price for one [unit] of [value], falling back to the box list price.
  static double priceFor(Product value, String unit) {
    final boxes = value.boxesPerCarton;
    if (unit == 'carton' && boxes > 0) {
      return value.cartonPrice ?? value.salePrice * boxes;
    }
    return value.boxPrice ?? value.salePrice;
  }

  void setProduct(Product value) {
    product = value;
    productId = value.id;
    costSnapshot = value.costPrice;
    if (descriptionController.text.trim().isEmpty) {
      descriptionController.text = value.name;
    }
    sellUnit = value.boxesPerCarton > 0 ? 'carton' : 'unit';
    quantityController.text = '1';
    priceController.text = format(priceFor(value, sellUnit));
  }

  /// Restores the display unit for a line loaded from the database. Stored
  /// quantities/prices are always per base box, while the editor shows the
  /// line in its original sell unit (carton or box).
  void applyLoadedProduct(Product value) {
    product = value;
    productId = value.id;
    costSnapshot ??= value.costPrice;
    if (sellUnit != 'carton' || value.boxesPerCarton <= 0) return;
    final baseQty = quantity;
    final basePrice = price;
    if (baseQty >= value.boxesPerCarton &&
        baseQty % value.boxesPerCarton == 0) {
      quantityController.text = format(baseQty / value.boxesPerCarton);
      priceController.text = format(basePrice * value.boxesPerCarton);
    } else {
      // The stored quantity cannot be expressed as whole cartons.
      sellUnit = 'unit';
    }
  }

  /// Switches the sell unit while keeping the line total where possible.
  void changeUnit(String unit) {
    final value = product;
    if (value == null || unit == sellUnit) return;
    final baseQty = baseQuantity;
    final total = quantity * price;
    final boxes = value.boxesPerCarton;
    sellUnit = unit;
    if (unit == 'carton' && boxes > 0) {
      if (baseQty >= boxes && baseQty % boxes == 0) {
        final cartons = baseQty ~/ boxes;
        quantityController.text = format(cartons.toDouble());
        priceController.text = format(total / cartons);
      } else {
        quantityController.text = '1';
        priceController.text = format(priceFor(value, 'carton'));
      }
    } else {
      quantityController.text = format(baseQty.toDouble());
      priceController.text = format(
        baseQty == 0 ? priceFor(value, 'unit') : total / baseQty,
      );
    }
  }

  Map<String, dynamic> toJson() {
    final description = descriptionController.text.trim();
    // Without a resolved product the stored values are already per box, so the
    // line is sent as a base unit to avoid a second conversion on the server.
    final effectiveUnit = product == null ? 'unit' : sellUnit;
    return <String, dynamic>{
      'productId': product?.id ?? productId,
      'description': description.isEmpty ? (product?.name ?? '') : description,
      'quantity': quantity,
      'unitPrice': price,
      'discount': discount,
      'taxRate': taxRate,
      'sellUnit': effectiveUnit,
      'unitCost': costSnapshot,
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
    this.showProfit = false,
  });

  final List<InvoiceLineDraft> lines;
  final VoidCallback onChanged;
  final String? customerId;
  final bool enabled;

  /// Admin-only profit view while the invoice is being entered.
  final bool showProfit;

  @override
  State<InvoiceLinesEditor> createState() => _InvoiceLinesEditorState();
}

class _InvoiceLinesEditorState extends State<InvoiceLinesEditor> {
  /// The product currently staged in the quick-add bar.
  Product? _quickProduct;
  LastSalePrice? _lastPrice;
  String _quickUnit = 'unit';
  final TextEditingController _quickQty = TextEditingController(text: '1');
  final TextEditingController _quickPrice = TextEditingController();
  final FocusNode _qtyFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();

  List<InvoiceLineDraft> get lines => widget.lines;
  bool get enabled => widget.enabled;

  int get _quickRequestedBoxes {
    final quantity = double.tryParse(_quickQty.text.trim())?.round() ?? 0;
    final boxes = _quickProduct?.boxesPerCarton ?? 0;
    return _quickUnit == 'carton' && boxes > 0 ? quantity * boxes : quantity;
  }

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
    final unit = product.boxesPerCarton > 0 ? 'carton' : 'unit';
    setState(() {
      _quickProduct = product;
      _quickUnit = unit;
      _lastPrice = null;
      _quickPrice.text = InvoiceLineDraft.format(
        InvoiceLineDraft.priceFor(product, unit),
      );
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
      // The stored last price is per base box; show it in the chosen unit.
      final factor =
          _quickUnit == 'carton' && product.boxesPerCarton > 0
              ? product.boxesPerCarton
              : 1;
      final display = LastSalePrice(
        unitPrice: last.unitPrice * factor,
        sellUnit: factor > 1 ? 'carton' : 'box',
        invoiceNumber: last.invoiceNumber,
        issueDate: last.issueDate,
      );
      setState(() {
        _lastPrice = display;
        _quickPrice.text = InvoiceLineDraft.format(display.unitPrice);
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
    final price = double.tryParse(_quickPrice.text.trim()) ??
        InvoiceLineDraft.priceFor(product, _quickUnit);
    final line = InvoiceLineDraft(
      productId: product.id,
      quantity: quantity.toDouble(),
      price: price,
      taxRate: product.taxRate,
      sellUnit: _quickUnit,
    );
    line.product = product;
    line.costSnapshot = product.costPrice;
    line.descriptionController.text = product.name;
    setState(() {
      lines.add(line);
      _quickProduct = null;
      _lastPrice = null;
      _quickUnit = 'unit';
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
    final revenue = lines.fold<double>(0, (sum, line) => sum + line.revenue);
    final cost = lines.fold<double>(0, (sum, line) => sum + line.cost);

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
              StockOnHandHint(
                product: _quickProduct,
                requestedQuantity: _quickRequestedBoxes,
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  if ((_quickProduct?.boxesPerCarton ?? 0) > 0) ...<Widget>[
                    SizedBox(
                      width: 104,
                      child: DropdownButtonFormField<String>(
                        value: _quickUnit == 'carton' ? 'carton' : 'box',
                        decoration: const InputDecoration(
                          labelText: null,
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                            value: 'box',
                            child: Text(s.box),
                          ),
                          DropdownMenuItem(
                            value: 'carton',
                            child: Text(s.carton),
                          ),
                        ],
                        onChanged: enabled
                            ? (value) {
                                final product = _quickProduct;
                                if (value == null || product == null) return;
                                setState(() {
                                  _quickUnit = value;
                                  _lastPrice = null;
                                  _quickPrice.text =
                                      InvoiceLineDraft.format(
                                    InvoiceLineDraft.priceFor(product, value),
                                  );
                                });
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: AppNumberField(
                      label: s.qty,
                      controller: _quickQty,
                      focusNode: _qtyFocus,
                      enabled: enabled,
                      decimal: false,
                      onChanged: (_) => setState(() {}),
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        s.lineCountLabel,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${lines.where((line) => line.isValid).length}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _SummaryRow(label: s.subtotal, value: subtotal),
              _SummaryRow(label: s.discountWord, value: -discountTotal),
              _SummaryRow(label: s.tax, value: taxTotal),
              const Divider(),
              _SummaryRow(label: s.total, value: total, emphasise: true),
            ],
          ),
        ),
        if (widget.showProfit) ...<Widget>[
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
                _SummaryRow(
                  label: s.netProfit,
                  value: revenue - cost,
                  emphasise: true,
                ),
              ],
            ),
          ),
        ],
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
                if (line.boxesPerCarton > 0) ...<Widget>[
                  SizedBox(
                    width: 104,
                    child: DropdownButtonFormField<String>(
                      value: line.sellUnit == 'carton' ? 'carton' : 'box',
                      decoration: const InputDecoration(
                        labelText: null,
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      items: <DropdownMenuItem<String>>[
                        DropdownMenuItem(value: 'box', child: Text(s.box)),
                        DropdownMenuItem(
                          value: 'carton',
                          child: Text(s.carton),
                        ),
                      ],
                      onChanged: widget.enabled
                          ? (value) {
                              if (value == null) return;
                              line.changeUnit(value);
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
                requestedQuantity: line.baseQuantity,
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
