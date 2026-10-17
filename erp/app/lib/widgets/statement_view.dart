import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/l10n.dart';
import '../models/account_statement.dart';
import 'money_text.dart';
import 'section_card.dart';

/// Renders an account statement: partner header, ledger rows and totals.
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
                  style: theme.textTheme.bodyMedium
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
        const SizedBox(height: 16),
        SectionCard(
          title: s.ledger,
          subtitle: s.entriesCount(rows.length),
          child: rows.isEmpty
              ? Text(
                  s.noEntriesForPeriod,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                )
              : Column(
                  children: <Widget>[
                    const Divider(height: 8),
                    for (final row in rows) _LedgerTile(row: row),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: s.totals,
          child: Column(
            children: <Widget>[
              _TotalRow(
                label: s.openingBalance,
                amount: statement.openingBalance,
              ),
              _TotalRow(label: s.totalDebit, amount: statement.totalDebit),
              _TotalRow(label: s.totalCredit, amount: statement.totalCredit),
              const Divider(),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.row});

  final StatementRow row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final isPayment = row.type == 'PAYMENT';
    final title = row.description.isNotEmpty
        ? row.description
        : (row.number.isNotEmpty ? row.number : s.status(row.type));
    final subtitle = <String>[
      Formatters.dateTime(row.date),
      if (row.number.isNotEmpty && row.description.isNotEmpty) row.number,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isPayment
                ? Icons.payments_outlined
                : Icons.receipt_long_outlined,
            size: 20,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.bodyMedium),
                Text(
                  s.status(row.type),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isPayment ? Colors.teal : theme.colorScheme.primary,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (row.debit > 0)
                _SignedAmount(label: s.dr, amount: row.debit),
              if (row.credit > 0)
                _SignedAmount(label: s.cr, amount: row.credit),
              if (row.debit <= 0 && row.credit <= 0)
                Text(
                  '—',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${s.bal} ',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  MoneyText(
                    row.balance,
                    colorNegative: true,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignedAmount extends StatelessWidget {
  const _SignedAmount({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$label ',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        MoneyText(amount, style: theme.textTheme.bodyMedium),
      ],
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
    final style =
        emphasise ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          MoneyText(
            amount,
            colorNegative: emphasise,
            style: style?.copyWith(
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
