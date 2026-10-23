import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../state/reports_controller.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../shell/navigation.dart';
import 'general_ledger_screen.dart';
import 'report_widgets.dart';

// ---------------------------------------------------------------------------
// Trial balance (ميزان المراجعة)
// ---------------------------------------------------------------------------

/// Debit / credit totals for every account.
class TrialBalanceReportScreen extends StatelessWidget {
  const TrialBalanceReportScreen({super.key});

  Future<void> _reload(BuildContext context) =>
      context.read<ReportsController>().loadTrialBalance();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final rows = asMapList(controller.trialBalanceReport['rows']);
    final totals = asMap(controller.trialBalanceReport['totals']);
    final debit = asDouble(totals['debit']);
    final credit = asDouble(totals['credit']);
    return ReportAsyncSection(
      loading: controller.loadingTrialBalance,
      error: controller.trialBalanceError,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noAccounts,
      emptyIcon: Icons.balance_outlined,
      onRetry: () => _reload(context),
      children: <Widget>[
        ReportTotalsCard(
          title: s.totals,
          subtitle: (debit - credit).abs() < 0.01 ? s.balanced : s.notBalanced,
          rows: <Widget>[
            ReportKeyValueRow(label: s.debit, amount: debit),
            ReportKeyValueRow(label: s.credit, amount: credit),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.trialBalance,
          subtitle: s.trialBalanceHint,
          child: Column(
            children: <Widget>[
              for (final row in rows) _AccountRow(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = asString(row['code']);
    final name = asString(row['name']);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('$code $name'.trim()),
      subtitle: Text(
        '${context.s.debit}: ${Formatters.money(asDouble(row['debit']))} · '
        '${context.s.credit}: ${Formatters.money(asDouble(row['credit']))}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: MoneyText(
        asDouble(row['balance']),
        colorNegative: true,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Income statement (قائمة الدخل)
// ---------------------------------------------------------------------------

/// Revenue minus expenses for a period.
class IncomeStatementReportScreen extends StatefulWidget {
  const IncomeStatementReportScreen({super.key});

  @override
  State<IncomeStatementReportScreen> createState() =>
      _IncomeStatementReportScreenState();
}

class _IncomeStatementReportScreenState
    extends State<IncomeStatementReportScreen> {
  DateTime? _from;
  DateTime? _to;

  void _reload() => context
      .read<ReportsController>()
      .loadIncomeStatement(from: _from, to: _to);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final revenue = asMapList(controller.incomeStatement['revenue']);
    final expenses = asMapList(controller.incomeStatement['expenses']);
    final totals = asMap(controller.incomeStatement['totals']);
    final netProfit = asDouble(totals['netProfit']);
    return ReportAsyncSection(
      loading: controller.loadingIncomeStatement,
      error: controller.incomeStatementError,
      isEmpty: revenue.isEmpty && expenses.isEmpty,
      emptyTitle: s.noDataForFilters,
      emptyIcon: Icons.trending_up_outlined,
      onRetry: () async => _reload(),
      header: ReportHeader(
        filters: <Widget>[
          DateRangeButton(
            from: _from,
            to: _to,
            onChanged: (from, to) {
              setState(() {
                _from = from;
                _to = to;
              });
              _reload();
            },
          ),
        ],
      ),
      children: <Widget>[
        ReportTotalsCard(
          title: s.totals,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.revenue,
              amount: asDouble(totals['revenue']),
            ),
            ReportKeyValueRow(
              label: s.expenses,
              amount: asDouble(totals['expenses']),
            ),
            ReportKeyValueRow(label: s.netProfit, amount: netProfit),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.revenue,
          child: _EmptyOrRows(
            rows: revenue,
            emptyLabel: s.noDataForFilters,
            from: _from,
            to: _to,
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.expenses,
          child: _EmptyOrRows(
            rows: expenses,
            emptyLabel: s.noDataForFilters,
            from: _from,
            to: _to,
          ),
        ),
      ],
    );
  }
}

class _EmptyOrRows extends StatelessWidget {
  const _EmptyOrRows({
    required this.rows,
    required this.emptyLabel,
    this.from,
    this.to,
  });

  final List<Map<String, dynamic>> rows;
  final String emptyLabel;
  final DateTime? from;
  final DateTime? to;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        emptyLabel,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Column(
      children: <Widget>[
        for (final row in rows)
          _StatementRow(row: row, from: from, to: to),
      ],
    );
  }
}

class _StatementRow extends StatelessWidget {
  const _StatementRow({required this.row, this.from, this.to});

  final Map<String, dynamic> row;
  final DateTime? from;
  final DateTime? to;

  @override
  Widget build(BuildContext context) {
    final code = asString(row['code']);
    final name = asString(row['name']);
    final accountId = asString(row['accountId']);
    return InkWell(
      onTap: accountId.isEmpty
          ? null
          : () => pushScreen<void>(
                context,
                '$code $name'.trim(),
                GeneralLedgerScreen(
                  initialAccountId: accountId,
                  initialFrom: from,
                  initialTo: to,
                ),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: <Widget>[
            Expanded(child: Text('$code $name'.trim())),
            MoneyText(asDouble(row['amount']), colorNegative: true),
            if (accountId.isNotEmpty) ...<Widget>[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Balance sheet (الميزانية العمومية)
// ---------------------------------------------------------------------------

/// Assets, liabilities and equity as of a date.
class BalanceSheetReportScreen extends StatefulWidget {
  const BalanceSheetReportScreen({super.key});

  @override
  State<BalanceSheetReportScreen> createState() =>
      _BalanceSheetReportScreenState();
}

class _BalanceSheetReportScreenState extends State<BalanceSheetReportScreen> {
  DateTime? _asOf;

  void _reload() =>
      context.read<ReportsController>().loadBalanceSheet(asOf: _asOf);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final data = controller.balanceSheet;
    final assets = asMapList(data['assets']);
    final liabilities = asMapList(data['liabilities']);
    final equity = asMapList(data['equity']);
    final totals = asMap(data['totals']);
    final balanced = asBool(totals['balanced'], fallback: true);
    return ReportAsyncSection(
      loading: controller.loadingBalanceSheet,
      error: controller.balanceSheetError,
      isEmpty: assets.isEmpty && liabilities.isEmpty && equity.isEmpty,
      emptyTitle: s.noDataForFilters,
      emptyIcon: Icons.account_balance_outlined,
      onRetry: () async => _reload(),
      header: ReportHeader(
        filters: <Widget>[
          AppDateField(
            label: s.asOf,
            value: _asOf,
            onChanged: (value) {
              setState(() => _asOf = value);
              _reload();
            },
          ),
        ],
      ),
      children: <Widget>[
        ReportTotalsCard(
          title: s.totals,
          subtitle: balanced ? s.balanced : s.notBalanced,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.assets,
              amount: asDouble(totals['assets']),
            ),
            ReportKeyValueRow(
              label: s.liabilities,
              amount: asDouble(totals['liabilities']),
            ),
            ReportKeyValueRow(
              label: s.equity,
              amount: asDouble(totals['equity']),
            ),
            ReportKeyValueRow(
              label: s.netProfit,
              amount: asDouble(totals['netProfit']),
            ),
            const Divider(),
            ReportKeyValueRow(
              label: '${s.liabilities} + ${s.equity}',
              amount: asDouble(totals['liabilitiesAndEquity']),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.assets,
          child: _StatementRows(rows: assets, to: _asOf),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.liabilities,
          child: _StatementRows(rows: liabilities, to: _asOf),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.equity,
          child: _StatementRows(rows: equity, to: _asOf),
        ),
      ],
    );
  }
}

class _StatementRows extends StatelessWidget {
  const _StatementRows({required this.rows, this.to});

  final List<Map<String, dynamic>> rows;
  final DateTime? to;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (rows.isEmpty) {
      return Text(s.noDataForFilters, style: Theme.of(context).textTheme.bodyMedium);
    }
    return Column(
      children: <Widget>[
        for (final row in rows) _StatementRow(row: row, to: to),
      ],
    );
  }
}
