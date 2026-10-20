import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../state/reports_controller.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Expenses grouped by category, month and cash box for the chosen period.
class ExpenseReportScreen extends StatefulWidget {
  const ExpenseReportScreen({super.key});

  @override
  State<ExpenseReportScreen> createState() => _ExpenseReportScreenState();
}

class _ExpenseReportScreenState extends State<ExpenseReportScreen> {
  DateTime? _from;
  DateTime? _to;

  void _reload() => context
      .read<ReportsController>()
      .loadExpenseReport(from: _from, to: _to);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final categories = asMapList(controller.expenseReport['categories']);
    final months = asMapList(controller.expenseReport['months']);
    final boxes = asMapList(controller.expenseReport['boxes']);
    final total = asDouble(controller.expenseReport['total']);
    final count = asInt(controller.expenseReport['count']);

    return ReportAsyncSection(
      loading: controller.loadingExpenseReport,
      error: controller.expenseReportError,
      isEmpty: categories.isEmpty && months.isEmpty,
      emptyTitle: s.noDataForFilters,
      emptyIcon: Icons.call_made,
      onRetry: () async => _reload(),
      header: ReportHeader(
        onPrint: () =>
            PrintService.printExpenseReport(context, from: _from, to: _to),
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
          title: s.expenseReport,
          subtitle: s.expenseReportHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.expenseCount,
              value: Formatters.integer(count),
            ),
            ReportKeyValueRow(label: s.total, amount: total),
          ],
        ),
        const SizedBox(height: 12),
        if (categories.isNotEmpty)
          SectionCard(
            title: s.expensesByCategory,
            child: Column(
              children: <Widget>[
                for (final row in categories)
                  _BreakdownRow(
                    label: asString(row['name'], fallback: s.uncategorized),
                    meta: Formatters.integer(asInt(row['count'])),
                    amount: asDouble(row['amount']),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (months.isNotEmpty)
          SectionCard(
            title: s.expensesByMonth,
            child: Column(
              children: <Widget>[
                for (final row in months)
                  _BreakdownRow(
                    label: asString(row['month']),
                    amount: asDouble(row['amount']),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (boxes.isNotEmpty)
          SectionCard(
            title: s.expensesByBox,
            child: Column(
              children: <Widget>[
                for (final row in boxes)
                  _BreakdownRow(
                    label: asString(row['name'], fallback: s.cashBox),
                    amount: asDouble(row['amount']),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.label, this.meta, required this.amount});

  final String label;
  final String? meta;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (meta != null && meta!.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Text(
                meta!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          MoneyText(amount, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
