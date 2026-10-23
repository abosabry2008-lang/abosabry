import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../models/account.dart';
import '../../models/expense.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

/// Manages expense categories (تصنيفات المصروفات): list, add, edit, delete.
class ExpenseCategoriesScreen extends StatefulWidget {
  const ExpenseCategoriesScreen({super.key, this.initialCategory});

  final ExpenseCategory? initialCategory;

  @override
  State<ExpenseCategoriesScreen> createState() =>
      _ExpenseCategoriesScreenState();
}

class _ExpenseCategoriesScreenState extends State<ExpenseCategoriesScreen> {
  List<ExpenseCategory> _categories = <ExpenseCategory>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.initialCategory != null) {
        _openForm(category: widget.initialCategory);
      }
    });
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await api.getList('/expenses/categories');
      if (!mounted) return;
      setState(() => _categories = rows.map(ExpenseCategory.fromJson).toList());
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({ExpenseCategory? category}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryFormDialog(category: category),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _printStatement(ExpenseCategory category) async {
    final s = context.s;
    final range = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => _StatementRangeDialog(title: s.printCategoryStatement),
    );
    if (range == null || !mounted) return;
    await PrintService.printExpenseCategoryStatement(
      context,
      category.id,
      from: range.start,
      to: range.end,
    );
  }

  Future<void> _delete(ExpenseCategory category) async {
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.deleteExpenseCategoryQ,
      message: category.name,
      destructive: true,
      confirmLabel: s.delete,
    );
    if (!confirmed || !mounted) return;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.delete('/expenses/categories/${category.id}');
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(s.expenseCategoryDeleted)));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final canWrite = context.watch<Session>().can('expenses.write');

    if (_loading && _categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _categories.isEmpty) {
      return Center(child: Text(_error!));
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: <Widget>[
          if (_categories.isEmpty)
            SectionCard(
              title: s.noExpenseCategories,
              subtitle: s.expenseCategoriesHint,
              child: const SizedBox.shrink(),
            )
          else
            for (final category in _categories)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(category.name.substring(0, 1).toUpperCase()),
                  ),
                  title: Text(category.name),
                  subtitle: Text(
                    <String>[
                      '${s.expenseCount}: ${category.expenseCount}',
                      if (category.accountCode != null)
                        '${category.accountCode} ${category.accountName ?? ''}',
                      '${s.openingBalance}: ${Formatters.money(category.openingBalance)}',
                    ].join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (!category.active)
                        StatusChip(
                          status: 'INACTIVE',
                          label: s.inactive,
                          compact: true,
                        ),
                      if (canWrite)
                        IconButton(
                          tooltip: s.edit,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openForm(category: category),
                        ),
                      IconButton(
                        tooltip: s.printCategoryStatement,
                        icon: const Icon(Icons.print_outlined),
                        onPressed: () => _printStatement(category),
                      ),
                      if (canWrite)
                        IconButton(
                          tooltip: s.delete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(category),
                        ),
                    ],
                  ),
                  onTap: canWrite ? () => _openForm(category: category) : null,
                ),
              ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: Text(s.newExpenseCategory),
            )
          : null,
    );
  }
}

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({this.category});

  final ExpenseCategory? category;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.category?.name ?? '');
  late String? _accountCode = widget.category?.accountCode;
  late final TextEditingController _openingBalance = TextEditingController(
    text: (widget.category?.openingBalance ?? 0).toString(),
  );
  late bool _active = widget.category?.active ?? true;
  bool _saving = false;
  List<Account> _accounts = <Account>[];

  bool get _isEdit => widget.category != null;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _name.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final rows = await context.read<Session>().api.getList('/accounting/accounts');
      if (!mounted) return;
      setState(() {
        // Expense categories belong on P&L accounts. Keep the current link even
        // if it points somewhere else so an existing category never breaks.
        _accounts = rows
            .map(Account.fromJson)
            .where((account) =>
                account.type == 'EXPENSE' || account.code == _accountCode)
            .toList();
      });
    } on ApiException {
      // The account link is optional.
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final s = context.s;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'accountCode': _accountCode,
      'openingBalance': double.tryParse(_openingBalance.text.trim()) ?? 0,
      'active': _active,
    };
    try {
      if (_isEdit) {
        await api.patchObject('/expenses/categories/${widget.category!.id}', body: body);
      } else {
        await api.postObject('/expenses/categories', body: body);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? s.expenseCategoryUpdated : s.categorySaved)),
      );
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
    final accountOptions = <SelectOption<String?>>[
      const SelectOption<String?>(null, '—'),
      ..._accounts.map(
        (account) =>
            SelectOption<String?>(
              account.code,
              '${account.code} · ${account.name} · ${context.s.status(account.type)}',
            ),
      ),
    ];
    return AlertDialog(
      title: Text(_isEdit ? s.editExpenseCategory : s.newExpenseCategory),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppTextField(
                label: s.name,
                controller: _name,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? s.nameRequired : null,
              ),
              const SizedBox(height: 12),
              AppNumberField(
                label: s.openingBalance,
                controller: _openingBalance,
                prefixIcon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(height: 12),
              AppSelectField<String?>(
                label: s.accountOptional,
                value: _accountCode,
                options: accountOptions,
                onChanged: (value) => setState(() => _accountCode = value),
              ),
              const SizedBox(height: 8),
              AppSwitchField(
                label: s.active,
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? s.saving : s.save),
        ),
      ],
    );
  }
}

/// Asks for a statement period, defaulting to the current month.
class _StatementRangeDialog extends StatefulWidget {
  const _StatementRangeDialog({required this.title});

  final String title;

  @override
  State<_StatementRangeDialog> createState() => _StatementRangeDialogState();
}

class _StatementRangeDialogState extends State<_StatementRangeDialog> {
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _to = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(s.categoryStatementRange),
          const SizedBox(height: 12),
          DateRangeButton(
            from: _from,
            to: _to,
            onChanged: (from, to) => setState(() {
              _from = from ?? _from;
              _to = to ?? _to;
            }),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
            DateTimeRange(start: _from, end: _to),
          ),
          icon: const Icon(Icons.print_outlined),
          label: Text(s.print),
        ),
      ],
    );
  }
}
