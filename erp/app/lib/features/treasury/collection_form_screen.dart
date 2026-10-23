import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/cash_box.dart';
import '../../models/customer.dart';
import '../../models/user.dart';
import '../../state/settings_controller.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';

/// Bulk collection receipt: enter one amount per customer in a single list.
///
/// This is the screen agents use for around 50 customers at a time, so it
/// deliberately avoids per-line pickers. The customers are filtered by the
/// selected salesperson, searched by name/code/phone, and every row keeps its
/// own amount. "Collect all balances" fills the whole sheet in one tap.
class CollectionFormScreen extends StatefulWidget {
  const CollectionFormScreen({super.key});

  @override
  State<CollectionFormScreen> createState() => _CollectionFormScreenState();
}

class _CollectionFormScreenState extends State<CollectionFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final Map<String, TextEditingController> _amounts =
      <String, TextEditingController>{};

  List<CashBox> _boxes = <CashBox>[];
  List<Customer> _customers = <Customer>[];
  List<AppUser> _salespeople = <AppUser>[];

  String? _boxId;
  String? _salespersonId;
  String _search = '';
  DateTime _collectedAt = DateTime.now();
  bool _showAll = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reference.dispose();
    _note.dispose();
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    try {
      final boxRows = await api.getList('/treasury/boxes');
      final people = await api.getList('/users/salespersons');

      // `/customers` caps a page at 100 rows, so walk the pages instead of
      // silently missing customers past the first hundred.
      final customers = <Customer>[];
      var page = 1;
      while (true) {
        final result = await api.getPage<Customer>(
          '/customers',
          query: <String, dynamic>{'page': page, 'pageSize': 100},
          parse: Customer.fromJson,
        );
        customers.addAll(result.items);
        if (!result.hasMore || result.items.isEmpty) break;
        page += 1;
      }

      if (!mounted) return;
      setState(() {
        _boxes = boxRows.map(CashBox.fromJson).toList();
        _customers = customers;
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

  TextEditingController _controllerFor(String customerId) {
    return _amounts.putIfAbsent(
      customerId,
      () => TextEditingController()..addListener(_recalculate),
    );
  }

  void _recalculate() {
    if (mounted) setState(() {});
  }

  double _amountFor(String customerId) =>
      double.tryParse(_amounts[customerId]?.text.trim() ?? '') ?? 0;

  Iterable<Customer> get _receiptCustomers sync* {
    for (final customer in _customers) {
      if (!customer.active) continue;
      if (_salespersonId != null && customer.salespersonId != _salespersonId) {
        continue;
      }
      yield customer;
    }
  }

  List<Customer> get _visibleCustomers {
    final query = _search.trim().toLowerCase();
    final rows = <Customer>[];
    for (final customer in _receiptCustomers) {
      final amount = _amountFor(customer.id);
      if (!_showAll && customer.balance == 0 && amount <= 0) continue;
      if (query.isNotEmpty) {
        final haystack =
            '${customer.name} ${customer.code ?? ''} ${customer.phone ?? ''}'
                .toLowerCase();
        if (!haystack.contains(query)) continue;
      }
      rows.add(customer);
    }
    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  int get _enteredCount =>
      _receiptCustomers.where((customer) => _amountFor(customer.id) > 0).length;

  double get _total => _receiptCustomers.fold<double>(
        0,
        (sum, customer) => sum + _amountFor(customer.id),
      );

  void _setAmount(Customer customer, double amount) {
    final text = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    _controllerFor(customer.id).text = text;
  }

  void _collectAll() {
    for (final customer in _visibleCustomers) {
      if (customer.balance > 0) _setAmount(customer, customer.balance);
    }
    setState(() {});
  }

  void _clearAmounts() {
    for (final customer in _visibleCustomers) {
      _amounts[customer.id]?.clear();
    }
    setState(() {});
  }

  void _changeSalesperson(String? value) {
    final next = (value == null || value.isEmpty) ? null : value;
    if (next == _salespersonId) return;
    setState(() {
      _salespersonId = next;
      // Amounts belong to the previous salesperson's sheet; drop the ones that
      // are no longer on this receipt so nothing is saved by accident.
      if (next != null) {
        for (final customer in _customers) {
          if (customer.salespersonId != next) {
            _amounts[customer.id]?.clear();
          }
        }
      }
    });
  }

  Future<void> _submit() async {
    final s = context.s;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_boxId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.chooseBox)));
      return;
    }

    final lines = <Map<String, dynamic>>[];
    for (final customer in _receiptCustomers) {
      final amount = _amountFor(customer.id);
      if (amount <= 0) continue;
      lines.add(<String, dynamic>{
        'customerId': customer.id,
        'amount': amount,
        'note': null,
      });
    }
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.noAmountsEntered)));
      return;
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
          'lines': lines,
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

    final currencyCode = context.watch<SettingsController?>()?.baseCurrencyCode;
    final boxOptions = _boxes
        .where((box) => box.active)
        .map(
          (box) => SelectOption<String>(
            box.id,
            '${box.name} · '
            '${Formatters.money(box.balance, currencyCode: currencyCode)}',
          ),
        )
        .toList();
    final visible = _visibleCustomers;
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        children: <Widget>[
          Expanded(
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
                      AppSelectField<String?>(
                        label: s.salesperson,
                        value: _salespersonId,
                        hint: s.chooseSalesperson,
                        enabled: !_saving,
                        prefixIcon: Icons.badge_outlined,
                        options: <SelectOption<String?>>[
                          SelectOption<String?>(null, s.allSalespeople),
                          for (final person in _salespeople)
                            SelectOption<String?>(person.id, person.name),
                        ],
                        onChanged: _changeSalesperson,
                      ),
                      const SizedBox(height: 14),
                      AppDateField(
                        label: s.date,
                        value: _collectedAt,
                        enabled: !_saving,
                        clearable: false,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _collectedAt = value);
                          }
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
                  title: s.customersToCollect,
                  subtitle: s.collectionsHint,
                  child: Column(
                    children: <Widget>[
                      AppSearchField(
                        hintText: s.searchCustomersHint,
                        onChanged: (value) => setState(() => _search = value),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          FilledButton.tonalIcon(
                            onPressed: _saving ? null : _collectAll,
                            icon: const Icon(Icons.done_all, size: 18),
                            label: Text(s.collectAll),
                          ),
                          TextButton.icon(
                            onPressed: _saving ? null : _clearAmounts,
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: Text(s.clearAmounts),
                          ),
                          TextButton.icon(
                            onPressed: _saving
                                ? null
                                : () =>
                                    setState(() => _showAll = !_showAll),
                            icon: Icon(
                              _showAll
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 18,
                            ),
                            label: Text(s.showAllCustomers),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(s.noMatches),
                        )
                      else
                        for (var index = 0; index < visible.length; index++)
                          _CustomerAmountRow(
                            key: ValueKey<String>(visible[index].id),
                            index: index,
                            customer: visible[index],
                            controller: _controllerFor(visible[index].id),
                            amount: _amountFor(visible[index].id),
                            enabled: !_saving,
                            onFullBalance: visible[index].balance > 0
                                ? () => _setAmount(
                                      visible[index],
                                      visible[index].balance,
                                    )
                                : null,
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${s.customersToCollect}: $_enteredCount',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        s.voucherTotal,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(width: 8),
                      MoneyText(
                        _total,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerAmountRow extends StatelessWidget {
  const _CustomerAmountRow({
    super.key,
    required this.index,
    required this.customer,
    required this.controller,
    required this.amount,
    required this.enabled,
    this.onFullBalance,
  });

  final int index;
  final Customer customer;
  final TextEditingController controller;
  final double amount;
  final bool enabled;
  final VoidCallback? onFullBalance;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final remaining = customer.balance - amount;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: <Widget>[
                    if (customer.code != null)
                      Text(
                        customer.code!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    Text(
                      '${s.balance}: ',
                      style: theme.textTheme.bodySmall,
                    ),
                    MoneyText(
                      customer.balance,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (amount > 0) ...<Widget>[
                      Text(
                        ' · ${s.remainingBalance}: ',
                        style: theme.textTheme.bodySmall,
                      ),
                      MoneyText(
                        remaining,
                        colorNegative: true,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: TextField(
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.end,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                hintText: '0.00',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            tooltip: s.fullBalance,
            visualDensity: VisualDensity.compact,
            onPressed: enabled ? onFullBalance : null,
            icon: const Icon(Icons.price_check_outlined),
          ),
        ],
      ),
    );
  }
}
