import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/cash_box.dart';
import '../../models/expense.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

const List<String> expenseMethods = <String>[
  'CASH',
  'CARD',
  'BANK_TRANSFER',
  'MOBILE_MONEY',
  'CHEQUE',
  'OTHER',
];

/// Creates or edits an expense (مصروف) — a cash outflow from a cash box.
class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({
    super.key,
    this.expense,
    this.categories = const <ExpenseCategory>[],
    this.boxes = const <CashBox>[],
  });

  final Expense? expense;
  final List<ExpenseCategory> categories;
  final List<CashBox> boxes;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _amount = TextEditingController(
    text: widget.expense == null ? '' : widget.expense!.amount.toStringAsFixed(2),
  );
  late final TextEditingController _payee =
      TextEditingController(text: widget.expense?.payee ?? '');
  late final TextEditingController _reference =
      TextEditingController(text: widget.expense?.reference ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.expense?.note ?? '');

  List<ExpenseCategory> _categories = <ExpenseCategory>[];
  List<CashBox> _boxes = <CashBox>[];
  String? _categoryId;
  String? _cashBoxId;
  late String _method = widget.expense?.method ?? 'CASH';
  late DateTime _date = widget.expense?.spentAt ?? DateTime.now();
  bool _loading = true;
  bool _saving = false;

  bool get _editing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.expense?.categoryId;
    _cashBoxId = widget.expense?.cashBoxId;
    _categories = widget.categories;
    _boxes = widget.boxes;
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    if (_categories.isEmpty) {
      try {
        final rows = await api.getList('/expenses/categories');
        if (!mounted) return;
        _categories = rows.map(ExpenseCategory.fromJson).toList();
      } on ApiException {
        // Keep whatever we were given.
      }
    }
    if (_boxes.isEmpty) {
      try {
        final rows = await api.getList('/treasury/boxes');
        if (!mounted) return;
        _boxes = rows.map(CashBox.fromJson).toList();
      } on ApiException {
        // Keep whatever we were given.
      }
    }
    if (!mounted) return;
    setState(() {
      _cashBoxId ??= _boxes.isNotEmpty ? _boxes.first.id : null;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final s = context.s;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final body = <String, dynamic>{
      'categoryId': _categoryId,
      'cashBoxId': _cashBoxId,
      'amount': double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0,
      'method': _method,
      'payee': _payee.text.trim().isEmpty ? null : _payee.text.trim(),
      'reference':
          _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      'spentAt': _date.toIso8601String(),
    };
    try {
      if (_editing) {
        await api.patchObject('/expenses/${widget.expense!.id}', body: body);
        messenger.showSnackBar(SnackBar(content: Text(s.expenseUpdated)));
      } else {
        await api.postObject('/expenses', body: body);
        messenger.showSnackBar(SnackBar(content: Text(s.expenseSaved)));
      }
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
    final categoryOptions = <SelectOption<String?>>[
      SelectOption<String?>(null, s.uncategorized),
      ..._categories
          .where((category) => category.active)
          .map((category) => SelectOption<String?>(category.id, category.name)),
    ];
    final boxOptions = _boxes
        .where((box) => box.active)
        .map(
          (box) => SelectOption<String?>(
            box.id,
            '${box.name} · ${Formatters.money(box.balance)}',
          ),
        )
        .toList();
    final selectedBox = _boxes
        .where((box) => box.id == _cashBoxId)
        .cast<CashBox?>()
        .firstWhere((box) => true, orElse: () => null);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: _editing ? s.editExpense : s.newExpense,
            child: Column(
              children: <Widget>[
                AppSelectField<String?>(
                  label: s.expenseCategory,
                  value: _categoryId,
                  enabled: !_saving,
                  prefixIcon: Icons.category_outlined,
                  options: categoryOptions,
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 14),
                AppNumberField(
                  label: s.expenseAmount,
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
                AppSelectField<String?>(
                  label: s.cashBox,
                  value: _cashBoxId,
                  enabled: !_saving,
                  prefixIcon: Icons.account_balance_wallet_outlined,
                  options: boxOptions,
                  onChanged: (value) => setState(() => _cashBoxId = value),
                ),
                if (selectedBox != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    '${s.openingBalance}: '
                    '${Formatters.money(selectedBox.openingBalance)} · '
                    '${s.balance}: ${Formatters.money(selectedBox.balance)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                AppSelectField<String>(
                  label: s.method,
                  value: _method,
                  enabled: !_saving,
                  prefixIcon: Icons.credit_card_outlined,
                  options: expenseMethods
                      .map((method) =>
                          SelectOption<String>(method, s.status(method)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _method = value ?? 'CASH'),
                ),
                const SizedBox(height: 14),
                AppDateField(
                  label: s.expenseDate,
                  value: _date,
                  enabled: !_saving,
                  clearable: false,
                  onChanged: (value) {
                    if (value != null) setState(() => _date = value);
                  },
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: s.payee,
                  controller: _payee,
                  enabled: !_saving,
                  prefixIcon: Icons.person_outline,
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
}
