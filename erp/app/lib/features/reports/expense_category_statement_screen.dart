import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Statement of one expense category: brought-forward balance, expenses,
/// settlements and the running balance after every movement.
class ExpenseCategoryStatementScreen extends StatefulWidget {
  const ExpenseCategoryStatementScreen({super.key});

  @override
  State<ExpenseCategoryStatementScreen> createState() =>
      _ExpenseCategoryStatementScreenState();
}

class _ExpenseCategoryStatementScreenState
    extends State<ExpenseCategoryStatementScreen> {
  late DateTime _from;
  late DateTime _to;
  String? _categoryId;
  List<Map<String, dynamic>> _categories = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCategories());
  }

  Future<void> _loadCategories() async {
    try {
      final rows = await context.read<Session>().api.getList('/expenses/categories');
      if (!mounted) return;
      setState(() {
        _categories = rows.map(asMap).toList();
        if (_categories.isNotEmpty) {
          _categoryId = asString(_categories.first['id']);
        }
      });
    } catch (_) {
      // The report shows its own error when the category cannot be loaded.
    }
    await _load();
  }

  Future<void> _load() async {
    final categoryId = _categoryId;
    if (categoryId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _data = <String, dynamic>{};
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.getObject(
            '/expenses/report',
            query: <String, dynamic>{
              'categoryId': categoryId,
              'from': _from.toUtc().toIso8601String(),
              'to': Formatters.isoRangeEnd(_to),
            },
          );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.s.couldNotLoadReport;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final entries = asMapList(_data['entries']);
    final opening = asDouble(_data['openingBalance']);
    final closing = asDouble(_data['closingBalance']);
    final totalDebit = asDouble(_data['totalDebit']);
    final totalCredit = asDouble(_data['totalCredit']);
    String? categoryName;
    for (final row in _categories) {
      if (asString(row['id']) == _categoryId) {
        categoryName = asString(row['name'], fallback: '—');
        break;
      }
    }

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: _categoryId == null ||
          (entries.isEmpty && opening == 0 && closing == 0),
      emptyTitle: _categories.isEmpty
          ? s.noExpenseCategories
          : s.noCategoryStatementMoves,
      emptyIcon: Icons.receipt_long_outlined,
      onRetry: _loadCategories,
      header: ReportHeader(
        onPrint: _categoryId == null
            ? null
            : () => PrintService.printExpenseCategoryStatement(
                  context,
                  _categoryId!,
                  from: _from,
                  to: _to,
                ),
        filters: <Widget>[
          AppSelectField<String>(
            label: s.expenseCategory,
            value: _categoryId ?? '',
            hint: s.expenseCategory,
            prefixIcon: Icons.category_outlined,
            options: <SelectOption<String>>[
              for (final category in _categories)
                SelectOption<String>(
                  asString(category['id']),
                  asString(category['name']),
                ),
            ],
            onChanged: (value) {
              setState(() => _categoryId = value);
              _load();
            },
          ),
          DateRangeButton(
            from: _from,
            to: _to,
            onChanged: (from, to) {
              setState(() {
                if (from != null) _from = from;
                if (to != null) _to = to;
              });
              _load();
            },
          ),
          FilledButton.tonalIcon(
            onPressed: _load,
            icon: const Icon(Icons.search),
            label: Text(s.search),
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: categoryName == null
              ? s.expenseCategoryStatement
              : '${s.expenseCategoryStatement} — $categoryName',
          subtitle: s.expenseCategoryStatementHint,
          child: Text(
            s.expenseCategoryStatementExplainer,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 12),
        ReportTotalsCard(
          title: s.expenseCategoryStatement,
          subtitle: s.expenseCategoryStatementHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.broughtForward,
              amount: opening,
            ),
            ReportKeyValueRow(label: s.totalDebit, amount: totalDebit),
            ReportKeyValueRow(label: s.totalCredit, amount: totalCredit),
            ReportKeyValueRow(
              label: s.closingBalance,
              amount: closing,
              emphasise: true,
            ),
            ReportKeyValueRow(
              label: s.countLabel,
              value: Formatters.integer(entries.length),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.expenseCategoryStatement,
          subtitle: s.expenseCategoryStatementHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 16,
              columns: <DataColumn>[
                DataColumn(label: Text(s.date)),
                DataColumn(label: Text(s.numberLabel)),
                DataColumn(label: Text(s.type)),
                DataColumn(label: Text(s.description)),
                DataColumn(label: Text(s.cashBox)),
                DataColumn(label: Text(s.totalDebit), numeric: true),
                DataColumn(label: Text(s.totalCredit), numeric: true),
                DataColumn(label: Text(s.balance), numeric: true),
              ],
              rows: <DataRow>[
                DataRow(
                  color: WidgetStatePropertyAll<Color>(
                    theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                  ),
                  cells: <DataCell>[
                    const DataCell(Text('—')),
                    const DataCell(Text('—')),
                    DataCell(
                      Text(
                        s.broughtForward,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    DataCell(
                      MoneyText(
                        opening,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                for (final entry in entries)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(Text(Formatters.date(asDate(entry['date'])))),
                      DataCell(Text(asString(entry['number'], fallback: '—'))),
                      DataCell(Text(_entryType(s, entry))),
                      DataCell(
                        SizedBox(
                          width: 300,
                          child: Text(
                            asString(entry['description'], fallback: '—'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: Text(
                            asString(entry['cashBox'], fallback: '—'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        asDouble(entry['debit']) == 0
                            ? const Text('')
                            : MoneyText(asDouble(entry['debit'])),
                      ),
                      DataCell(
                        asDouble(entry['credit']) == 0
                            ? const Text('')
                            : MoneyText(asDouble(entry['credit'])),
                      ),
                      DataCell(
                        MoneyText(
                          asDouble(entry['balance']),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                DataRow(
                  color: WidgetStatePropertyAll<Color>(
                    theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                  ),
                  cells: <DataCell>[
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    DataCell(
                      Text(
                        s.total,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    DataCell(
                      MoneyText(
                        totalDebit,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      MoneyText(
                        totalCredit,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      MoneyText(
                        closing,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _entryType(AppStrings s, Map<String, dynamic> entry) {
    if (asString(entry['kind']) != 'SETTLEMENT') return s.expense;
    return asString(entry['direction']) == 'DECREASE'
        ? s.settlementDecreaseEntry
        : s.settlementIncreaseEntry;
  }
}
