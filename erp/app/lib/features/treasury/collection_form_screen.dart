import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/cash_box.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../models/user.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/searchable_picker_field.dart';
import '../../widgets/section_card.dart';

/// One editable line of the collection receipt.
class _LineDraft {
  _LineDraft();

  final TextEditingController amount = TextEditingController();
  final TextEditingController note = TextEditingController();
  String? customerId;
  String? invoiceId;

  double get parsedAmount => double.tryParse(amount.text.trim()) ?? 0;

  void dispose() {
    amount.dispose();
    note.dispose();
  }
}

/// Records one receipt for an agent covering several customers/invoices.
class CollectionFormScreen extends StatefulWidget {
  const CollectionFormScreen({super.key});

  @override
  State<CollectionFormScreen> createState() => _CollectionFormScreenState();
}

class _CollectionFormScreenState extends State<CollectionFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final List<_LineDraft> _lines = <_LineDraft>[_LineDraft()];

  List<CashBox> _boxes = <CashBox>[];
  List<Customer> _customers = <Customer>[];
  List<Invoice> _invoices = <Invoice>[];
  List<AppUser> _salespeople = <AppUser>[];

  String? _boxId;
  String? _salespersonId;
  DateTime _collectedAt = DateTime.now();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final line in _lines) {
      line.amount.addListener(_recalculate);
    }
    _load();
  }

  @override
  void dispose() {
    _reference.dispose();
    _note.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _recalculate() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    try {
      final boxRows = await api.getList('/treasury/boxes');
      final customerPage = await api.getPage<Customer>(
        '/customers',
        query: <String, dynamic>{'page': 1, 'pageSize': 300},
        parse: Customer.fromJson,
      );
      final invoicePage = await api.getPage<Invoice>(
        '/invoices',
        query: <String, dynamic>{'page': 1, 'pageSize': 300, 'unpaid': 'true'},
        parse: Invoice.fromJson,
      );
      final people = await api.getList('/users/salespersons');
      if (!mounted) return;
      setState(() {
        _boxes = boxRows.map(CashBox.fromJson).toList();
        _customers = customerPage.items;
        _invoices = invoicePage.items;
        _salespeople = people.map(AppUser.fromJson).toList();
        _boxId ??= _boxes.isEmpty
            ? null
            : _boxes.firstWhere(
                (box) => box.isDefault,
                orElse: () => _boxes.first,
              ).id;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Invoice? _invoiceById(String? id) {
    if (id == null) return null;
    for (final invoice in _invoices) {
      if (invoice.id == id) return invoice;
    }
    return null;
  }

  void _addLine() {
    final line = _LineDraft()
      ..amount.addListener(_recalculate);
    setState(() {
      // Inherit salesperson/customer context from previous line
      if (_salespersonId != null) {
        // Will be filtered in UI
      }
      _lines.add(line);
    });
  }

  void _removeLine(_LineDraft line) {
    if (_lines.length == 1) return;
    setState(() => _lines.remove(line));
    line.dispose();
  }

  double get _total =>
      _lines.fold<double>(0, (sum, line) => sum + line.parsedAmount);

  Future<void> _submit() async {
    final s = context.s;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_boxId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.chooseBox)));
      return;
    }
    for (final line in _lines) {
      final invoice = _invoiceById(line.invoiceId);
      final customerId = line.customerId ?? invoice?.customerId;
      if (customerId == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.lineNeedsCustomer)));
        return;
      }
      if (line.parsedAmount <= 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.lineNeedsAmount)));
        return;
      }
    }

    setState(() => _saving = true);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await api.postObject(
        '/treasury/collections',
        body: <String, dynamic>{
          'cashBoxId': _boxId,
          'salespersonId': _salespersonId,
          'collectedAt': _collectedAt.toIso8601String(),
          'reference': _reference.text.trim().isEmpty
              ? null
              : _reference.text.trim(),
          'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
          'lines': _lines
              .map(
                (line) => <String, dynamic>{
                  'customerId': line.customerId,
                  'invoiceId': line.invoiceId,
                  'amount': line.parsedAmount,
                  'note': line.note.text.trim().isEmpty
                      ? null
                      : line.note.text.trim(),
                },
              )
              .toList(),
        },
      );
      messenger.showSnackBar(SnackBar(content: Text(s.collectionSaved)));
      navigator.pop(true);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final boxOptions = _boxes
        .where((box) => box.active)
        .map(
          (box) => SelectOption<String>(
            box.id,
            '${box.name} · ${Formatters.money(box.balance)}',
          ),
        )
        .toList();

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: s.newCollection,
            child: Column(
              children: <Widget>[
                AppSelectField<String>(
                  label: s.cashBox,
                  value: _boxId,
                  hint: s.chooseBox,
                  enabled: !_saving,
                  prefixIcon: Icons.account_balance_wallet_outlined,
                  options: boxOptions,
                  onChanged: (value) => setState(() => _boxId = value),
                ),
                const SizedBox(height: 14),
                SearchablePickerField(
                  label: s.salesperson,
                  value: _salespersonId,
                  hint: s.chooseSalesperson,
                  enabled: !_saving,
                  prefixIcon: Icons.badge_outlined,
                  searchHint: s.searchHint,
                  clearable: true,
                  options: _salespeople
                      .map(
                        (user) => PickerOption(value: user.id, label: user.name),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _salespersonId =
                        (value == null || value.isEmpty) ? null : value;
                    // When salesperson changes, clear lines' customers that don't belong to them
                    if (_salespersonId != null) {
                      for (final line in _lines) {
                        if (line.customerId != null) {
                          final cust = _customers
                              .where((c) => c.id == line.customerId)
                              .firstOrNull;
                          if (cust == null || cust.salespersonId != _salespersonId) {
                            line.customerId = null;
                            line.invoiceId = null;
                          }
                        }
                      }
                    }
                  }),
                ),
                const SizedBox(height: 14),
                AppDateField(
                  label: s.date,
                  value: _collectedAt,
                  enabled: !_saving,
                  clearable: false,
                  onChanged: (value) {
                    if (value != null) setState(() => _collectedAt = value);
                  },
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: s.reference,
                  controller: _reference,
                  enabled: !_saving,
                  prefixIcon: Icons.tag_outlined,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: s.note,
                  controller: _note,
                  enabled: !_saving,
                  maxLines: 2,
                  prefixIcon: Icons.notes_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: s.collectionLines,
            child: Column(
              children: <Widget>[
                for (var index = 0; index < _lines.length; index++)
                  _LineEditor(
                    key: ObjectKey(_lines[index]),
                    index: index,
                    line: _lines[index],
                    enabled: !_saving,
                    customers: _customers,
                    invoices: _invoices
                        .where(
                          (invoice) =>
                              _lines[index].customerId == null ||
                              invoice.customerId == _lines[index].customerId,
                        )
                        .toList(),
                    invoice: _invoiceById(_lines[index].invoiceId),
                    salespersonId: _salespersonId,
                    onCustomerChanged: (value) {
                      setState(() {
                        _lines[index].customerId = value;
                        final invoice = _invoiceById(_lines[index].invoiceId);
                        if (invoice != null && invoice.customerId != value) {
                          _lines[index].invoiceId = null;
                        }
                      });
                    },
                    onInvoiceChanged: (value) {
                      setState(() {
                        final line = _lines[index];
                        line.invoiceId =
                            (value == null || value.isEmpty) ? null : value;
                        final invoice = _invoiceById(line.invoiceId);
                        if (invoice != null) {
                          line.customerId ??= invoice.customerId;
                          if ((double.tryParse(line.amount.text.trim()) ?? 0) <=
                              0) {
                            final amount =
                                invoice.balance > 0 ? invoice.balance : invoice.total;
                            line.amount.text = Formatters.number(amount);
                          }
                        }
                      });
                    },
                    onRemove: _lines.length > 1
                        ? () => _removeLine(_lines[index])
                        : null,
                  ),
                const SizedBox(height: 2),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _addLine,
                    icon: const Icon(Icons.add),
                    label: Text(s.addLine),
                  ),
                ),
                const Divider(height: 28),
                Row(
                  children: <Widget>[
                    Text(
                      s.voucherTotal,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    MoneyText(
                      _total,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
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
                  child: Text(s.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: const Icon(Icons.check),
                  label: Text(_saving ? s.saving : s.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    super.key,
    required this.index,
    required this.line,
    required this.enabled,
    required this.customers,
    required this.invoices,
    required this.invoice,
    required this.onCustomerChanged,
    required this.onInvoiceChanged,
    required this.onRemove,
    this.salespersonId,
  });

  final int index;
  final _LineDraft line;
  final bool enabled;
  final List<Customer> customers;
  final List<Invoice> invoices;
  final Invoice? invoice;
  final ValueChanged<String?> onCustomerChanged;
  final ValueChanged<String?> onInvoiceChanged;
  final VoidCallback? onRemove;
  final String? salespersonId;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 12,
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Text(
                  '${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  tooltip: s.delete,
                  onPressed: enabled ? onRemove : null,
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
          SearchablePickerField(
            label: s.customer,
            value: line.customerId,
            hint: s.selectCustomer,
            enabled: enabled,
            prefixIcon: Icons.person_outline,
            searchHint: s.searchCustomersHint,
            options: customers
                .where((c) => salespersonId == null || c.salespersonId == salespersonId)
                .map(
                  (customer) => customerPickerOption(
                    id: customer.id,
                    name: customer.name,
                    code: customer.code,
                    balance: customer.balance,
                  ),
                )
                .toList(),
            onChanged: onCustomerChanged,
          ),
          const SizedBox(height: 14),
          SearchablePickerField(
            label: s.invoice,
            value: line.invoiceId,
            hint: s.noInvoice,
            enabled: enabled,
            prefixIcon: Icons.receipt_long_outlined,
            searchHint: s.searchInvoicesHint,
            clearable: line.invoiceId != null,
            options: invoices
                .map(
                  (item) => PickerOption(
                    value: item.id,
                    label: item.number,
                    trailing: Formatters.money(item.balance),
                    keywords: <String>[if (item.customerName != null) item.customerName!],
                  ),
                )
                .toList(),
            onChanged: onInvoiceChanged,
          ),
          const SizedBox(height: 14),
          AppNumberField(
            label: s.amount,
            controller: line.amount,
            enabled: enabled,
            prefixIcon: Icons.payments_outlined,
            helperText: invoice == null
                ? null
                : '${s.balance}: ${Formatters.money(invoice!.balance)}',
            validator: (value) {
              final parsed = double.tryParse((value ?? '').trim());
              if (parsed == null || parsed <= 0) return s.lineNeedsAmount;
              return null;
            },
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: s.note,
            controller: line.note,
            enabled: enabled,
            prefixIcon: Icons.notes_outlined,
          ),
        ],
      ),
    );
  }
}
