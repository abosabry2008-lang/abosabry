import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/cash_box.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../models/supplier.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/searchable_picker_field.dart';
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
    this.cashBoxId,
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

  /// Pre-selected cash box (the default box is used when omitted).
  final String? cashBoxId;

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
  String? _cashBoxId;
  DateTime _paidAt = DateTime.now();

  List<Customer> _customers = <Customer>[];
  List<Supplier> _suppliers = <Supplier>[];
  List<Invoice> _invoices = <Invoice>[];
  List<CashBox> _boxes = <CashBox>[];
  bool _loadingOptions = false;
  bool _saving = false;

  bool get _inbound => _direction == 'INBOUND';

  @override
  void initState() {
    super.initState();
    _invoiceId = widget.invoiceId;
    _customerId = widget.customerId;
    _supplierId = widget.supplierId;
    _cashBoxId = widget.cashBoxId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadOptions();
    });
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
      final boxes = await api.getList('/treasury/boxes');
      final List<Customer> customers;
      final List<Supplier> suppliers;
      final List<Invoice> invoices;
      if (widget.lockTarget) {
        customers = <Customer>[];
        suppliers = <Supplier>[];
        invoices = <Invoice>[];
      } else {
        final customerPage = await api.getPage<Customer>(
          '/customers',
          query: <String, dynamic>{'page': 1, 'pageSize': 100},
          parse: Customer.fromJson,
        );
        final supplierPage = await api.getPage<Supplier>(
          '/suppliers',
          query: <String, dynamic>{'page': 1, 'pageSize': 100},
          parse: Supplier.fromJson,
        );
        final invoicePage = await api.getPage<Invoice>(
          '/invoices',
          query: <String, dynamic>{'page': 1, 'pageSize': 100},
          parse: Invoice.fromJson,
        );
        customers = customerPage.items;
        suppliers = supplierPage.items;
        invoices = invoicePage.items;
      }
      if (!mounted) return;
      setState(() {
        _boxes = boxes.map(CashBox.fromJson).toList();
        _customers = customers;
        _suppliers = suppliers;
        _invoices = invoices;
        if (_cashBoxId == null) {
          for (final box in _boxes) {
            if (box.isDefault) {
              _cashBoxId = box.id;
              break;
            }
          }
          if (_cashBoxId == null && _boxes.isNotEmpty) {
            _cashBoxId = _boxes.first.id;
          }
        }
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
          'cashBoxId': _cashBoxId,
          'reference':
              _reference.text.trim().isEmpty ? null : _reference.text.trim(),
          'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
          'paidAt': _paidAt.toUtc().toIso8601String(),
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
                  AppSelectField<String>(
                    label: s.cashBox,
                    value: _cashBoxId,
                    hint: s.chooseBox,
                    enabled: !_saving && _boxes.isNotEmpty,
                    prefixIcon: Icons.account_balance_wallet_outlined,
                    options: _boxes
                        .map(
                          (box) => SelectOption<String>(
                            box.id,
                            '${box.name} · ${Formatters.money(box.balance)}',
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _cashBoxId = value),
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
                      SearchablePickerField(
                        label: context.s.customer,
                        value: _customerId,
                        hint: context.s.selectCustomer,
                        enabled: !_saving,
                        prefixIcon: Icons.person_outline,
                        searchHint: context.s.searchCustomersHint,
                        clearable: _customerId != null,
                        options: _customers
                            .map(
                              (customer) => customerPickerOption(
                                id: customer.id,
                                name: customer.name,
                                code: customer.code,
                                balance: customer.balance,
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _customerId = value),
                      )
                    else
                      SearchablePickerField(
                        label: context.s.supplier,
                        value: _supplierId,
                        hint: context.s.selectSupplier,
                        enabled: !_saving,
                        prefixIcon: Icons.local_shipping_outlined,
                        searchHint: context.s.searchSuppliersHint,
                        clearable: _supplierId != null,
                        options: _suppliers
                            .map(
                              (supplier) => PickerOption(
                                value: supplier.id,
                                label: supplier.name,
                                subtitle: supplier.code,
                                trailing: Formatters.money(supplier.balance),
                                keywords: <String>[
                                  if (supplier.code != null) supplier.code!
                                ],
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
                  child: SearchablePickerField(
                    label: context.s.invoice,
                    value: _invoiceId,
                    hint: context.s.noInvoice,
                    enabled: !_saving,
                    prefixIcon: Icons.receipt_long_outlined,
                    searchHint: context.s.searchInvoicesHint,
                    clearable: _invoiceId != null,
                    options: _invoices
                        .map(
                          (invoice) => PickerOption(
                            value: invoice.id,
                            label: invoice.number,
                            subtitle: invoice.customerName,
                            trailing: invoice.balance == 0
                                ? null
                                : Formatters.money(invoice.balance),
                          ),
                        )
                        .toList(),
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
