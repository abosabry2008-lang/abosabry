import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../models/product.dart';
import '../../state/customers_controller.dart';
import '../../state/invoices_controller.dart';
import '../../state/product_catalog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/last_purchase_price_hint.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../../widgets/stock_on_hand_hint.dart';
import '../inventory/product_picker_field.dart';

/// Editable draft invoice: customer, due date, notes and lines.
class InvoiceEditScreen extends StatefulWidget {
  const InvoiceEditScreen({super.key, required this.invoice});

  final Invoice invoice;

  @override
  State<InvoiceEditScreen> createState() => _InvoiceEditScreenState();
}

class _InvoiceEditScreenState extends State<InvoiceEditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _notes =
      TextEditingController(text: widget.invoice.notes ?? '');
  late String? _customerId = widget.invoice.customerId;
  late DateTime? _dueDate = widget.invoice.dueDate;
  late final List<_InvoiceLineDraft> _lines = widget.invoice.lines
      .map(_InvoiceLineDraft.fromLine)
      .toList();

  bool _linesDirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.read<CustomersController>().ensureLoaded();
      final catalog = context.read<ProductCatalog>();
      await catalog.ensureLoaded();
      if (!mounted) return;
      setState(() {
        for (final line in _lines) {
          if (line.product == null && line.productId != null) {
            line.product = catalog.byId(line.productId!);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  void _linesChanged() {
    _linesDirty = true;
    setState(() {});
  }

  Map<String, dynamic> _body() {
    return <String, dynamic>{
      'customerId': _customerId,
      'dueDate': _dueDate?.toIso8601String(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'lines': _lines.map((line) => line.toJson()).toList(),
    };
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_linesDirty) {
      if (_lines.isEmpty || _lines.any((line) => !line.isValid)) {
        _snack(context.s.eachLineNeedsProduct);
        return;
      }
    }
    setState(() => _saving = true);
    final controller = context.read<InvoicesController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await controller.updateInvoice(widget.invoice.id, _body());
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(context.s.invoiceUpdated)));
      navigator.pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final customers = context.watch<CustomersController>();

    // The customer's stored balance is what they owe overall. For an issued
    // invoice that already includes this invoice's own balance, so subtract it
    // to get the debt that existed before this invoice.
    final selectedCustomer = _customerId == null
        ? null
        : customers.items
            .where((customer) => customer.id == _customerId)
            .cast<Customer?>()
            .firstWhere((customer) => true, orElse: () => null);
    final counted = <String>{'ISSUED', 'PARTIALLY_PAID', 'PAID'}
        .contains(widget.invoice.status);
    final previousBalance = selectedCustomer == null
        ? 0.0
        : double.parse(
            (selectedCustomer.balance -
                    (counted ? widget.invoice.balance : 0))
                .toStringAsFixed(2),
          );

    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: s.invoiceDetails,
              subtitle: widget.invoice.number,
              child: Column(
                children: <Widget>[
                  AppSelectField<String>(
                    label: s.customer,
                    value: _customerId,
                    enabled: !_saving,
                    hint: s.walkInCustomer,
                    prefixIcon: Icons.person_outline,
                    options: customers.items
                        .map(
                          (customer) => SelectOption<String>(
                            customer.id,
                            customer.name,
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _customerId = value),
                  ),
                  const SizedBox(height: 14),
                  AppDateField(
                    label: s.dueDate,
                    value: _dueDate,
                    enabled: !_saving,
                    onChanged: (value) => setState(() => _dueDate = value),
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.notes,
                    controller: _notes,
                    enabled: !_saving,
                    maxLines: 2,
                    prefixIcon: Icons.notes_outlined,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (selectedCustomer != null) ...<Widget>[
              SectionCard(
                title: s.previousBalanceLabel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            s.customerPreviousBalanceHint(
                              selectedCustomer.name,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        MoneyText(previousBalance),
                      ],
                    ),
                    if (previousBalance != 0) ...<Widget>[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              s.totalDueLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          MoneyText(
                            double.parse(
                              (previousBalance +
                                      (counted
                                          ? 0
                                          : widget.invoice.balance))
                                  .toStringAsFixed(2),
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            SectionCard(
              title: s.lines,
              subtitle: s.productsAndServices,
              child: _InvoiceLinesEditor(
                lines: _lines,
                enabled: !_saving,
                onChanged: _linesChanged,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(false),
                    child: Text(s.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? s.saving : s.saveChanges),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mutable invoice line used by [InvoiceEditScreen].
class _InvoiceLineDraft {
  _InvoiceLineDraft({
    this.productId,
    String description = '',
    double quantity = 1,
    double price = 0,
    double discount = 0,
    double taxRate = 0,
  })  : descriptionController = TextEditingController(text: description),
        quantityController = TextEditingController(text: _format(quantity)),
        priceController = TextEditingController(text: _format(price)),
        discountController = TextEditingController(text: _format(discount)),
        taxController = TextEditingController(text: _format(taxRate));

  Product? product;
  String? productId;
  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController priceController;
  final TextEditingController discountController;
  final TextEditingController taxController;

  static String _format(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  factory _InvoiceLineDraft.fromLine(InvoiceLine line) => _InvoiceLineDraft(
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
      priceController.text = _format(value.salePrice);
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

class _InvoiceLinesEditor extends StatefulWidget {
  const _InvoiceLinesEditor({
    required this.lines,
    required this.onChanged,
    this.enabled = true,
  });

  final List<_InvoiceLineDraft> lines;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  State<_InvoiceLinesEditor> createState() => _InvoiceLinesEditorState();
}

class _InvoiceLinesEditorState extends State<_InvoiceLinesEditor> {
  /// The product currently staged in the quick-add bar.
  Product? _quickProduct;
  final TextEditingController _quickQty = TextEditingController(text: '1');
  final TextEditingController _quickPrice = TextEditingController();
  final FocusNode _qtyFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();

  List<_InvoiceLineDraft> get lines => widget.lines;
  bool get enabled => widget.enabled;

  @override
  void dispose() {
    _quickQty.dispose();
    _quickPrice.dispose();
    _qtyFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  /// Adds the staged product as a line and clears the bar for the next one.
  void _addQuickLine() {
    final product = _quickProduct;
    if (product == null) return;
    final quantity = double.tryParse(_quickQty.text.trim())?.round() ?? 0;
    if (quantity <= 0) return;
    final price = double.tryParse(_quickPrice.text.trim()) ?? product.salePrice;
    final line = _InvoiceLineDraft(
      productId: product.id,
      quantity: quantity.toDouble(),
      price: price,
      taxRate: product.taxRate,
    )..setProduct(product);
    setState(() {
      lines.add(line);
      _quickProduct = null;
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
        // Quick continuous-add bar: pick a product, set qty/price, press add
        // (or Enter) and it drops into the list below — no new-row button.
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
                onChanged: (value) {
                  setState(() {
                    _quickProduct = value;
                    _quickPrice.text = _InvoiceLineDraft._format(
                      value.salePrice,
                    );
                  });
                  _qtyFocus.requestFocus();
                },
              ),
              LastPurchasePriceHint(product: _quickProduct),
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

/// A compact, collapsed line row that expands for full editing.
class _CompactInvoiceLine extends StatefulWidget {
  const _CompactInvoiceLine({
    super.key,
    required this.line,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final _InvoiceLineDraft line;
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
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: widget.enabled
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge,
                        ),
                        Text(
                          '${line.quantity} × ${Formatters.money(line.price)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Formatters.money(line.lineTotal),
                    style: theme.textTheme.titleMedium,
                  ),
                  IconButton(
                    tooltip: s.removeLine,
                    onPressed: widget.enabled ? widget.onRemove : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ProductPickerField(
                    product: line.product,
                    enabled: widget.enabled,
                    onChanged: (value) {
                      line.setProduct(value);
                      widget.onChanged();
                    },
                  ),
                  LastPurchasePriceHint(product: line.product),
                  StockOnHandHint(
                    product: line.product,
                    requestedQuantity: line.quantity,
                  ),
                  const SizedBox(height: 8),
                  AppTextField(
                    label: s.description,
                    controller: line.descriptionController,
                    enabled: widget.enabled,
                    prefixIcon: Icons.notes_outlined,
                    onChanged: (_) => widget.onChanged(),
                  ),
                  const SizedBox(height: 8),
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
                ],
              ),
            ),
        ],
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
