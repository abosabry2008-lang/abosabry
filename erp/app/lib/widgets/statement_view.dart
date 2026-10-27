import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/l10n.dart';
import '../models/account_statement.dart';
import 'money_text.dart';
import 'section_card.dart';

/// Renders an account statement: partner header, ledger table and totals.
///
/// The layout mirrors an SAP account statement: header data first, then a
/// bordered ledger grid (opening balance, movements, running balance) and a
/// separate totals block.
class StatementView extends StatelessWidget {
  const StatementView({super.key, required this.statement});

  final AccountStatement statement;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final rows = statement.rows;
    final contact = <String>[
      if (statement.phone != null) statement.phone!,
      if (statement.email != null) statement.email!,
      if (statement.address != null) statement.address!,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionCard(
          title: statement.name,
          subtitle: contact.isEmpty ? null : contact,
          child: Column(
            children: <Widget>[
              _InfoRow(
                label: s.currentBalance,
                child: MoneyText(
                  statement.balance,
                  colorNegative: true,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _InfoRow(
                label: s.creditLimitLabel,
                child: MoneyText(
                  statement.creditLimit,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (statement.from != null || statement.to != null)
                _InfoRow(
                  label: s.period,
                  child: Text(
                    '${Formatters.date(statement.from)} – '
                    '${Formatters.date(statement.to)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.ledger,
          subtitle: s.entriesCount(rows.length),
          padding: EdgeInsets.zero,
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    s.noEntriesForPeriod,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : _LedgerTable(statement: statement),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.totals,
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
          child: Column(
            children: <Widget>[
              _TotalRow(
                label: s.openingBalance,
                amount: statement.openingBalance,
              ),
              _TotalRow(label: s.totalDebit, amount: statement.totalDebit),
              _TotalRow(label: s.totalCredit, amount: statement.totalCredit),
              const Divider(height: 12),
              _TotalRow(
                label: s.closingBalance,
                amount: statement.closingBalance,
                emphasise: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(120),
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.statement});

  final AccountStatement statement;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final bold = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final cells = <DataRow>[
      DataRow(
        color: WidgetStatePropertyAll<Color>(
          theme.colorScheme.surfaceContainerHighest.withAlpha(110),
        ),
        cells: <DataCell>[
          const DataCell(Text('')),
          const DataCell(Text('')),
          DataCell(
            Text(
              s.openingBalance,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const DataCell(Text('')),
          const DataCell(Text('')),
          DataCell(MoneyText(statement.openingBalance, style: bold)),
        ],
      ),
      for (final row in statement.rows)
        DataRow(
          cells: <DataCell>[
            DataCell(
              Text(
                Formatters.date(row.date),
                style: theme.textTheme.bodySmall,
              ),
            ),
            DataCell(
              Text(row.number, style: theme.textTheme.bodySmall),
            ),
            DataCell(
              SizedBox(
                width: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      row.description.isNotEmpty
                          ? row.description
                          : (row.number.isNotEmpty
                              ? row.number
                              : s.status(row.type)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      s.status(row.type),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: row.type == 'PAYMENT'
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DataCell(
              row.debit > 0
                  ? MoneyText(row.debit)
                  : const Text(''),
            ),
            DataCell(
              row.credit > 0
                  ? MoneyText(row.credit)
                  : const Text(''),
            ),
            DataCell(
              MoneyText(
                row.balance,
                colorNegative: true,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columnSpacing: 14,
        horizontalMargin: 8,
        dataRowMinHeight: 26,
        dataRowMaxHeight: 38,
        columns: <DataColumn>[
          DataColumn(label: Text(s.date), numeric: false),
          DataColumn(label: Text(s.numberLabel), numeric: false),
          DataColumn(label: Text(s.description), numeric: false),
          DataColumn(label: Text(s.debit), numeric: true),
          DataColumn(label: Text(s.credit), numeric: true),
          DataColumn(label: Text(s.balance), numeric: true),
        ],
        rows: cells,
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    this.emphasise = false,
  });

  final String label;
  final double amount;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: emphasise ? null : theme.colorScheme.onSurfaceVariant,
      fontWeight: emphasise ? FontWeight.w700 : FontWeight.w400,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: emphasise ? FontWeight.w700 : FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: labelStyle)),
          MoneyText(
            amount,
            colorNegative: emphasise,
            style: valueStyle,
          ),
        ],
      ),
    );
  }
}
