import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../models/invoice.dart';
import '../../models/product.dart';
import '../../state/customers_controller.dart';
import '../../state/invoices_controller.dart';
import '../../state/product_catalog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
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
    if (_lines.isEmpty) _lines.add(_InvoiceLineDraft());
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

class _InvoiceLinesEditor extends StatelessWidget {
  const _InvoiceLinesEditor({
    required this.lines,
    required this.onChanged,
    this.enabled = true,
  });

  final List<_InvoiceLineDraft> lines;
  final VoidCallback onChanged;
  final bool enabled;

  double get subtotal => lines.fold<double>(0, (sum, line) => sum + line.gross);

  double get discountTotal =>
      lines.fold<double>(0, (sum, line) => sum + line.discount);

  double get taxTotal =>
      lines.fold<double>(0, (sum, line) => sum + line.taxAmount);

  double get total => lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
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
                    AppTextField(
                      label: s.description,
                      controller: lines[index].descriptionController,
                      enabled: enabled,
                      prefixIcon: Icons.notes_outlined,
                      onChanged: (_) => onChanged(),
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
                            label: s.unitPrice,
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
                        Expanded(
                          child: AppNumberField(
                            label: s.discountWord,
                            controller: lines[index].discountController,
                            enabled: enabled,
                            onChanged: (_) => onChanged(),
                          ),
                        ),
                        const SizedBox(width: 8),
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
                  lines.add(_InvoiceLineDraft());
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
