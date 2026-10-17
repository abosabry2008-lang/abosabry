import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../models/supplier.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

const List<String> paymentDirections = <String>[
  'INBOUND',
  'OUTBOUND',
];

const List<String> paymentMethods = <String>[
  'CASH',
  'CARD',
  'BANK_TRANSFER',
  'MOBILE_MONEY',
  'CHEQUE',
  'OTHER',
];

/// Creates a payment, optionally linked to a customer, supplier or invoice.
class PaymentFormScreen extends StatefulWidget {
  const PaymentFormScreen({
    super.key,
    this.direction = 'INBOUND',
    this.invoiceId,
    this.invoiceLabel,
    this.customerId,
    this.customerName,
    this.supplierId,
    this.supplierName,
    this.initialAmount,
    this.lockTarget = false,
  });

  final String direction;
  final String? invoiceId;
  final String? invoiceLabel;
  final String? customerId;
  final String? customerName;
  final String? supplierId;
  final String? supplierName;
  final double? initialAmount;

  /// When true the direction and the linked record cannot be changed.
  final bool lockTarget;

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _amount = TextEditingController(
    text: widget.initialAmount == null
        ? ''
        : Formatters.number(widget.initialAmount),
  );
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _note = TextEditingController();

  late String _direction = widget.direction;
  String _method = 'CASH';
  String? _invoiceId;
  String? _customerId;
  String? _supplierId;
  DateTime _paidAt = DateTime.now();

  List<Customer> _customers = <Customer>[];
  List<Supplier> _suppliers = <Supplier>[];
  List<Invoice> _invoices = <Invoice>[];
  bool _loadingOptions = false;
  bool _saving = false;

  bool get _inbound => _direction == 'INBOUND';

  @override
  void initState() {
    super.initState();
    _invoiceId = widget.invoiceId;
    _customerId = widget.customerId;
    _supplierId = widget.supplierId;
    if (!widget.lockTarget) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadOptions();
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() => _loadingOptions = true);
    final api = context.read<Session>().api;
    try {
      final customers = await api.getPage<Customer>(
        '/customers',
        query: <String, dynamic>{'page': 1, 'pageSize': 100},
        parse: Customer.fromJson,
      );
      final suppliers = await api.getPage<Supplier>(
        '/suppliers',
        query: <String, dynamic>{'page': 1, 'pageSize': 100},
        parse: Supplier.fromJson,
      );
      final invoices = await api.getPage<Invoice>(
        '/invoices',
        query: <String, dynamic>{'page': 1, 'pageSize': 100},
        parse: Invoice.fromJson,
      );
      if (!mounted) return;
      setState(() {
        _customers = customers.items;
        _suppliers = suppliers.items;
        _invoices = invoices.items;
      });
    } on ApiException {
      // Leave the dropdowns empty; the form still submits the manual fields.
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Invoice? _invoiceById(String? id) {
    if (id == null) return null;
    for (final invoice in _invoices) {
      if (invoice.id == id) return invoice;
    }
    return null;
  }

  void _onInvoiceChanged(String? value) {
    setState(() {
      _invoiceId = (value == null || value.isEmpty) ? null : value;
      final invoice = _invoiceById(_invoiceId);
      if (invoice != null) {
        _customerId ??= invoice.customerId;
        if (_amount.text.trim().isEmpty) {
          final amount = invoice.balance > 0 ? invoice.balance : invoice.total;
          _amount.text = Formatters.number(amount);
        }
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await api.post(
        '/payments',
        body: <String, dynamic>{
          'direction': _direction,
          'method': _method,
          'amount': double.tryParse(_amount.text.trim()) ?? 0,
          'invoiceId': _invoiceId,
          'customerId': _customerId,
          'supplierId': _supplierId,
          'reference':
              _reference.text.trim().isEmpty ? null : _reference.text.trim(),
          'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
          'paidAt': _paidAt.toIso8601String(),
        },
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.s.paymentRecorded)),
      );
      navigator.pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: s.recordAPayment,
              child: Column(
                children: <Widget>[
                  AppSelectField<String>(
                    label: s.direction,
                    value: _direction,
                    enabled: !widget.lockTarget && !_saving,
                    prefixIcon: Icons.swap_horiz,
                    options: paymentDirections
                        .map(
                          (value) =>
                              SelectOption<String>(value, s.status(value)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _direction = value;
                        _invoiceId = null;
                        _customerId = null;
                        _supplierId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  AppSelectField<String>(
                    label: s.method,
                    value: _method,
                    enabled: !_saving,
                    prefixIcon: Icons.credit_card_outlined,
                    options: paymentMethods
                        .map(
                          (value) => SelectOption<String>(value, s.status(value)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _method = value ?? _method),
                  ),
                  const SizedBox(height: 14),
                  AppNumberField(
                    label: s.amount,
                    controller: _amount,
                    enabled: !_saving,
                    prefixIcon: Icons.payments_outlined,
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim());
                      if (parsed == null || parsed <= 0) {
                        return context.s.enterAmountGreaterThanZero;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  AppDateField(
                    label: s.paidOn,
                    value: _paidAt,
                    enabled: !_saving,
                    clearable: false,
                    onChanged: (value) {
                      if (value != null) setState(() => _paidAt = value);
                    },
                  ),
                ],
              ),
            ),
            if (widget.lockTarget &&
                (widget.invoiceLabel != null ||
                    widget.customerName != null ||
                    widget.supplierName != null)) ...<Widget>[
              const SizedBox(height: 16),
              SectionCard(
                title: context.s.details,
                child: Column(
                  children: <Widget>[
                    if (widget.invoiceLabel != null)
                      _InfoRow(label: context.s.invoice, value: widget.invoiceLabel!),
                    if (widget.customerName != null)
                      _InfoRow(label: context.s.customer, value: widget.customerName!),
                    if (widget.supplierName != null)
                      _InfoRow(label: context.s.supplier, value: widget.supplierName!),
                  ],
                ),
              ),
            ],
            if (!widget.lockTarget) ...<Widget>[
              const SizedBox(height: 16),
              SectionCard(
                title: _inbound ? context.s.customer : context.s.supplier,
                child: Column(
                  children: <Widget>[
                    if (_loadingOptions)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_inbound)
                      AppSelectField<String>(
                        label: context.s.customer,
                        value: _customerId,
                        hint: context.s.selectCustomer,
                        enabled: !_saving,
                        prefixIcon: Icons.person_outline,
                        options: _customers
                            .map(
                              (customer) => SelectOption<String>(
                                customer.id,
                                customer.name,
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _customerId = value),
                      )
                    else
                      AppSelectField<String>(
                        label: context.s.supplier,
                        value: _supplierId,
                        hint: context.s.selectSupplier,
                        enabled: !_saving,
                        prefixIcon: Icons.local_shipping_outlined,
                        options: _suppliers
                            .map(
                              (supplier) => SelectOption<String>(
                                supplier.id,
                                supplier.name,
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _supplierId = value),
                      ),
                  ],
                ),
              ),
              if (_inbound) ...<Widget>[
                const SizedBox(height: 16),
                SectionCard(
                  title: context.s.invoice,
                  child: AppSelectField<String>(
                    label: context.s.invoice,
                    value: _invoiceId ?? '',
                    enabled: !_saving,
                    prefixIcon: Icons.receipt_long_outlined,
                    options: <SelectOption<String>>[
                      SelectOption<String>('', context.s.noInvoice),
                      ..._invoices.map(
                        (invoice) => SelectOption<String>(
                          invoice.id,
                          invoice.number,
                        ),
                      ),
                    ],
                    onChanged: _onInvoiceChanged,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: context.s.details,
              child: Column(
                children: <Widget>[
                  AppTextField(
                    label: context.s.reference,
                    controller: _reference,
                    enabled: !_saving,
                    hint: context.s.chequeOrTransferRef,
                    prefixIcon: Icons.tag_outlined,
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: context.s.note,
                    controller: _note,
                    enabled: !_saving,
                    maxLines: 2,
                    prefixIcon: Icons.notes_outlined,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(false),
                    child: Text(context.s.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: const Icon(Icons.check),
                    label: Text(_saving ? context.s.saving : context.s.save),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
