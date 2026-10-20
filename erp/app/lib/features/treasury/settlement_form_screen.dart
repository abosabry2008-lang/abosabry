import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/account_settlement.dart';
import '../../models/customer.dart';
import '../../models/expense.dart';
import '../../models/supplier.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// Creates or edits an account settlement (تسوية) — an adjustment to a
/// customer, supplier or expense-category balance that never touches a cash box.
class SettlementFormScreen extends StatefulWidget {
  const SettlementFormScreen({super.key, this.settlement});

  final AccountSettlement? settlement;

  @override
  State<SettlementFormScreen> createState() => _SettlementFormScreenState();
}

class _SettlementFormScreenState extends State<SettlementFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _amount = TextEditingController(
    text: widget.settlement == null
        ? ''
        : widget.settlement!.amount.toStringAsFixed(2),
  );
  late final TextEditingController _reference =
      TextEditingController(text: widget.settlement?.reference ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.settlement?.note ?? '');

  late SettlementTarget _target =
      widget.settlement?.target ?? SettlementTarget.customer;
  late SettlementDirection _direction =
      widget.settlement?.direction ?? SettlementDirection.increase;

  String? _customerId;
  String? _supplierId;
  String? _categoryId;
  late DateTime _date = widget.settlement?.settledAt ?? DateTime.now();

  List<Customer> _customers = <Customer>[];
  List<Supplier> _suppliers = <Supplier>[];
  List<ExpenseCategory> _categories = <ExpenseCategory>[];

  bool _loading = true;
  bool _saving = false;

  bool get _editing => widget.settlement != null;

  @override
  void initState() {
    super.initState();
    _customerId = widget.settlement?.customerId;
    _supplierId = widget.settlement?.supplierId;
    _categoryId = widget.settlement?.categoryId;
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    try {
      final customerPage = await api.getPage<Customer>(
        '/customers',
        query: <String, dynamic>{'page': 1, 'pageSize': 200},
        parse: Customer.fromJson,
      );
      final supplierPage = await api.getPage<Supplier>(
        '/suppliers',
        query: <String, dynamic>{'page': 1, 'pageSize': 200},
        parse: Supplier.fromJson,
      );
      final categoryRows = await api.getList('/expenses/categories');
      if (!mounted) return;
      setState(() {
        _customers = customerPage.items;
        _suppliers = supplierPage.items;
        _categories = categoryRows.map(ExpenseCategory.fromJson).toList();
      });
    } on ApiException {
      // Leave the pickers empty; validation will still guard the submit.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_target == SettlementTarget.customer && _customerId == null) {
      _snack(context.s.selectCustomer);
      return;
    }
    if (_target == SettlementTarget.supplier && _supplierId == null) {
      _snack(context.s.selectSupplier);
      return;
    }
    if (_target == SettlementTarget.expenseCategory && _categoryId == null) {
      _snack(context.s.selectExpenseCategory);
      return;
    }

    setState(() => _saving = true);
    final s = context.s;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final body = <String, dynamic>{
      'target': settlementTargetToApi(_target),
      'direction': settlementDirectionToApi(_direction),
      'customerId': _target == SettlementTarget.customer ? _customerId : null,
      'supplierId': _target == SettlementTarget.supplier ? _supplierId : null,
      'categoryId':
          _target == SettlementTarget.expenseCategory ? _categoryId : null,
      'amount': double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0,
      'reference':
          _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      'settledAt': _date.toIso8601String(),
    };

    try {
      if (_editing) {
        await api.patchObject('/settlements/${widget.settlement!.id}', body: body);
        messenger.showSnackBar(SnackBar(content: Text(s.settlementUpdated)));
      } else {
        await api.postObject('/settlements', body: body);
        messenger.showSnackBar(SnackBar(content: Text(s.settlementSaved)));
      }
      navigator.pop(true);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final targetOptions = <SelectOption<SettlementTarget>>[
      SelectOption<SettlementTarget>(
        SettlementTarget.customer,
        s.settlementTargetCustomer,
      ),
      SelectOption<SettlementTarget>(
        SettlementTarget.supplier,
        s.settlementTargetSupplier,
      ),
      SelectOption<SettlementTarget>(
        SettlementTarget.expenseCategory,
        s.settlementTargetExpense,
      ),
    ];

    final directionOptions = <SelectOption<SettlementDirection>>[
      SelectOption<SettlementDirection>(
        SettlementDirection.increase,
        s.settlementIncrease,
      ),
      SelectOption<SettlementDirection>(
        SettlementDirection.decrease,
        s.settlementDecrease,
      ),
    ];

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: _editing ? s.editSettlement : s.newSettlement,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.settlementNoCashEffect,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppSelectField<SettlementTarget>(
                  label: s.settlementTarget,
                  value: _target,
                  enabled: !_saving && !_editing,
                  prefixIcon: Icons.person_outline,
                  options: targetOptions,
                  onChanged: (value) {
                    if (value != null) setState(() => _target = value);
                  },
                ),
                const SizedBox(height: 14),
                if (_target == SettlementTarget.customer)
                  _customerPicker(s)
                else if (_target == SettlementTarget.supplier)
                  _supplierPicker(s)
                else
                  _categoryPicker(s),
                const SizedBox(height: 14),
                AppSelectField<SettlementDirection>(
                  label: s.settlementDirection,
                  value: _direction,
                  enabled: !_saving,
                  prefixIcon: Icons.swap_vert,
                  options: directionOptions,
                  onChanged: (value) {
                    if (value != null) setState(() => _direction = value);
                  },
                ),
                const SizedBox(height: 14),
                AppNumberField(
                  label: s.settlementAmount,
                  controller: _amount,
                  enabled: !_saving,
                  prefixIcon: Icons.payments_outlined,
                  validator: (value) {
                    final parsed =
                        double.tryParse((value ?? '').trim().replaceAll(',', ''));
                    if (parsed == null || parsed <= 0) {
                      return s.enterAmountGreaterThanZero;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                AppDateField(
                  label: s.settlementDate,
                  value: _date,
                  enabled: !_saving,
                  clearable: false,
                  onChanged: (value) {
                    if (value != null) setState(() => _date = value);
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

  Widget _customerPicker(AppStrings s) {
    final options = _customers
        .where((customer) => customer.active)
        .map(
          (customer) => SelectOption<String>(
            customer.id,
            '${customer.name}${customer.balance != 0 ? ' · ${Formatters.money(customer.balance)}' : ''}',
          ),
        )
        .toList();
    return AppSelectField<String>(
      label: s.settlementAccount,
      value: _customerId,
      enabled: !_saving,
      prefixIcon: Icons.person_outline,
      options: options,
      onChanged: (value) => setState(() => _customerId = value),
    );
  }

  Widget _supplierPicker(AppStrings s) {
    final options = _suppliers
        .where((supplier) => supplier.active)
        .map(
          (supplier) => SelectOption<String>(
            supplier.id,
            '${supplier.name}${supplier.balance != 0 ? ' · ${Formatters.money(supplier.balance)}' : ''}',
          ),
        )
        .toList();
    return AppSelectField<String>(
      label: s.settlementAccount,
      value: _supplierId,
      enabled: !_saving,
      prefixIcon: Icons.local_shipping_outlined,
      options: options,
      onChanged: (value) => setState(() => _supplierId = value),
    );
  }

  Widget _categoryPicker(AppStrings s) {
    final options = _categories
        .where((category) => category.active)
        .map(
          (category) => SelectOption<String>(category.id, category.name),
        )
        .toList();
    return AppSelectField<String>(
      label: s.settlementAccount,
      value: _categoryId,
      enabled: !_saving,
      prefixIcon: Icons.category_outlined,
      options: options,
      onChanged: (value) => setState(() => _categoryId = value),
    );
  }
}
