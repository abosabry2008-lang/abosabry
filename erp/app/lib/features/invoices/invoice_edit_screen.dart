import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../state/customers_controller.dart';
import '../../state/invoices_controller.dart';
import '../../state/product_catalog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/searchable_picker_field.dart';
import '../../widgets/section_card.dart';
import 'invoice_lines_editor.dart';

/// Editable invoice: create a new one (issued immediately) or edit a draft /
/// issued invoice as an administrator.
class InvoiceEditScreen extends StatefulWidget {
  const InvoiceEditScreen({super.key, this.invoice});

  final Invoice? invoice;

  @override
  State<InvoiceEditScreen> createState() => _InvoiceEditScreenState();
}

class _InvoiceEditScreenState extends State<InvoiceEditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _notes =
      TextEditingController(text: widget.invoice?.notes ?? '');
  late String? _customerId = widget.invoice?.customerId;
  late DateTime? _dueDate = widget.invoice?.dueDate;
  late final List<InvoiceLineDraft> _lines =
      (widget.invoice?.lines ?? const <InvoiceLine>[])
          .map(InvoiceLineDraft.fromLine)
          .toList();

  bool _linesDirty = false;
  bool _saving = false;
  bool _showProfit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.read<CustomersController>().ensureCatalogLoaded();
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
      'dueDate': _dueDate?.toUtc().toIso8601String(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'lines': _lines.map((line) => line.toJson()).toList(),
    };
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_linesDirty || widget.invoice == null) {
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
      if (widget.invoice == null) {
        // A directly created invoice is issued immediately.
        await context.read<Session>().api.postObject(
          '/invoices',
          body: <String, dynamic>{..._body(), 'issue': true},
        );
        await controller.refresh();
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(context.s.invoiceIssued)),
        );
      } else {
        await controller.updateInvoice(widget.invoice!.id, _body());
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(context.s.invoiceUpdated)),
        );
      }
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
    final session = context.watch<Session>();
    final customers = context.watch<CustomersController>();
    final invoice = widget.invoice;

    // The customer's stored balance is what they owe overall. For an issued
    // invoice that already includes this invoice's own balance, so subtract it
    // to get the debt that existed before this invoice.
    final selectedCustomer = _customerId == null
        ? null
        : customers.items
            .where((customer) => customer.id == _customerId)
            .cast<Customer?>()
            .firstWhere((customer) => true, orElse: () => null);
    final counted = invoice != null &&
        <String>{'ISSUED', 'PARTIALLY_PAID', 'PAID'}.contains(invoice.status);
    final previousBalance = selectedCustomer == null
        ? 0.0
        : double.parse(
            (selectedCustomer.balance -
                    (counted ? invoice.balance : 0))
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
              subtitle: invoice?.number ?? s.createInvoice,
              child: Column(
                children: <Widget>[
                  SearchablePickerField(
                    label: '${s.customer} *',
                    value: _customerId,
                    enabled: !_saving,
                    hint: s.selectCustomer,
                    prefixIcon: Icons.person_outline,
                    searchHint: s.searchCustomersHint,
                    options: customers.catalog
                        .map(
                          (customer) => customerPickerOption(
                            id: customer.id,
                            name: customer.name,
                            code: customer.code,
                            balance: customer.balance,
                          ),
                        )
                        .toList(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return s.customerRequired;
                      }
                      return null;
                    },
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
                                      (counted ? 0 : (invoice?.balance ?? 0)))
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
              trailing: session.isAdmin
                  ? TextButton.icon(
                      onPressed: () =>
                          setState(() => _showProfit = !_showProfit),
                      icon: Icon(
                        _showProfit
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      label: Text(_showProfit ? s.hideProfit : s.showProfit),
                    )
                  : null,
              child: InvoiceLinesEditor(
                lines: _lines,
                customerId: _customerId,
                enabled: !_saving,
                showProfit: session.isAdmin && _showProfit,
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
                    label: Text(
                      _saving
                          ? s.saving
                          : invoice == null
                              ? s.createInvoice
                              : s.saveChanges,
                    ),
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
