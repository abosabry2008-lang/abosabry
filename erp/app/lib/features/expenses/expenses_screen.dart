import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/cash_box.dart';
import '../../models/expense.dart';
import '../../state/expenses_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/page_header.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../shell/navigation.dart';
import 'expense_categories_screen.dart';
import 'expense_form_screen.dart';

/// Expenses (المصروفات): recorded cash outflows grouped by category.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<ExpenseCategory> _categories = <ExpenseCategory>[];
  List<CashBox> _boxes = <CashBox>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExpensesController>().ensureLoaded();
    });
    _loadLookups();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    final api = context.read<Session>().api;
    try {
      final results = await Future.wait(<Future<List<Map<String, dynamic>>>>[
        api.getList('/expenses/categories'),
        api.getList('/treasury/boxes'),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0].map(ExpenseCategory.fromJson).toList();
        _boxes = results[1].map(CashBox.fromJson).toList();
      });
    } on ApiException {
      // Filters are optional; leave the lookups empty if they fail.
    }
  }

  Future<void> _openForm({Expense? expense}) async {
    final saved = await pushScreen<bool>(
      context,
      expense == null ? context.s.newExpense : context.s.editExpense,
      ExpenseFormScreen(
        expense: expense,
        categories: _categories,
        boxes: _boxes,
      ),
    );
    if (saved == true && mounted) {
      await context.read<ExpensesController>().refresh();
      await _loadLookups();
    }
  }

  Future<void> _cancel(Expense expense) async {
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.cancelExpenseQ,
      message: expense.number,
      destructive: true,
      confirmLabel: s.cancel,
    );
    if (!confirmed || !mounted) return;
    final api = context.read<Session>().api;
    final controller = context.read<ExpensesController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post('/expenses/${expense.id}/cancel');
      await controller.refresh();
      messenger.showSnackBar(SnackBar(content: Text(s.expenseCancelled)));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = context.watch<Session>();
    final canWrite = session.can('expenses.write');
    return Column(
      children: <Widget>[
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabs,
            tabs: <Widget>[
              Tab(text: s.expensesTitle, icon: const Icon(Icons.receipt_long_outlined)),
              Tab(text: s.expenseCategories, icon: const Icon(Icons.category_outlined)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: <Widget>[
              _expensesTab(s, canWrite),
              _categoriesTab(s, canWrite),
            ],
          ),
        ),
      ],
    );
  }

  Widget _expensesTab(AppStrings s, bool canWrite) {
    final isAdmin = context.watch<Session>().isAdmin;
    final controller = context.watch<ExpensesController>();
    final categoryOptions = <SelectOption<String>>[
      SelectOption<String>('', s.allExpenseCategories),
      ..._categories.map(
        (category) => SelectOption<String>(category.id, category.name),
      ),
    ];
    final boxOptions = <SelectOption<String>>[
      SelectOption<String>('', s.allBoxes),
      ..._boxes.map((box) => SelectOption<String>(box.id, box.name)),
    ];

    return Scaffold(
      body: Column(
        children: <Widget>[
          PageHeader(
            title: s.expensesTitle,
            subtitle: s.expensesHint,
            filters: <Widget>[
              AppSearchField(
                hintText: s.searchExpensesHint,
                initialValue: controller.search,
                onChanged: controller.searchWith,
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppDateField(
                      label: s.date,
                      value: controller.date,
                      clearable: false,
                      onChanged: (value) {
                        if (value != null) controller.filterByDate(value);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => controller.refresh(),
                    icon: const Icon(Icons.search),
                    label: Text(s.search),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppSelectField<String>(
                      label: s.expenseCategory,
                      value: controller.categoryId ?? '',
                      options: categoryOptions,
                      onChanged: (value) => controller.filterByCategory(
                        value == null || value.isEmpty ? null : value,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppSelectField<String>(
                      label: s.cashBox,
                      value: controller.cashBoxId ?? '',
                      options: boxOptions,
                      onChanged: (value) => controller.filterByCashBox(
                        value == null || value.isEmpty ? null : value,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncListView<Expense>(
              controller: controller,
              emptyIcon: Icons.receipt_long_outlined,
              emptyTitle: s.noExpenses,
              emptyMessage: s.expensesHint,
              itemBuilder: (context, expense, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFB26A00).withValues(alpha: 0.12),
                    child: const Icon(Icons.call_made, color: Color(0xFFB26A00)),
                  ),
                  title: Text(
                    expense.categoryName ?? s.uncategorized,
                    style: TextStyle(
                      decoration: expense.cancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    '${expense.number}'
                    '${expense.payee == null || expense.payee!.isEmpty ? '' : ' · ${expense.payee}'}'
                    ' · ${s.status(expense.method)}'
                    ' · ${Formatters.date(expense.spentAt)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          MoneyText(
                            -expense.amount,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (expense.cancelled)
                            StatusChip(
                              status: 'VOID',
                              label: s.cancelled,
                              compact: true,
                            ),
                        ],
                      ),
                      if (canWrite && !expense.cancelled)
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _openForm(expense: expense);
                            } else if (value == 'cancel') {
                              _cancel(expense);
                            }
                          },
                          itemBuilder: (context) => <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: Text(s.edit),
                            ),
                            if (isAdmin)
                              PopupMenuItem<String>(
                                value: 'cancel',
                                child: Text(s.cancelExpenseQ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  onTap: canWrite && !expense.cancelled
                      ? () => _openForm(expense: expense)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: Text(s.expense),
            )
          : null,
    );
  }

  Widget _categoriesTab(AppStrings s, bool canWrite) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          SectionCard(
            title: s.expenseCategories,
            subtitle: s.expenseCategoriesHint,
            child: Column(
              children: <Widget>[
                if (_categories.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(s.noExpenseCategories),
                  )
                else
                  for (final category in _categories)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(
                          category.name.substring(0, 1).toUpperCase(),
                        ),
                      ),
                      title: Text(category.name),
                      subtitle: Text(
                        '${s.expenseCount}: ${category.expenseCount}'
                        '${category.accountCode == null ? '' : ' · ${category.accountCode}'}',
                      ),
                      trailing: canWrite
                          ? IconButton(
                              tooltip: s.edit,
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ExpenseCategoriesScreen(
                                    initialCategory: category,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => pushScreen<void>(
                context,
                s.expenseCategories,
                const ExpenseCategoriesScreen(),
              ).then((_) => _loadLookups()),
              icon: const Icon(Icons.add),
              label: Text(s.newExpenseCategory),
            )
          : null,
    );
  }
}
