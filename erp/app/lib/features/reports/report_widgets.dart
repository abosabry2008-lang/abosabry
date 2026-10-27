import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';

/// Toolbar shown above a report body with a right-aligned print action.
class ReportPrintBar extends StatelessWidget {
  const ReportPrintBar({super.key, required this.onPrint});

  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: AppTheme.isLight(context)
            ? const Color(0xFFEDF1F5)
            : theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.table_chart_outlined,
            size: 16,
            color: AppTheme.groupTitleColor(context),
          ),
          const SizedBox(width: 6),
          Text(
            context.s.report,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppTheme.groupTitleColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined, size: 16),
            label: Text(context.s.print),
          ),
        ],
      ),
    );
  }
}

/// A print bar plus an optional row of filter controls, laid out as a compact
/// SAP-style report toolbar.
class ReportHeader extends StatelessWidget {
  const ReportHeader({super.key, this.onPrint, this.filters = const <Widget>[]});

  /// When `null` no print button is shown.
  final VoidCallback? onPrint;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) {
    final hasFilters = filters.isNotEmpty;
    if (onPrint == null && !hasFilters) return const SizedBox.shrink();
    final print = onPrint == null
        ? null
        : OutlinedButton.icon(
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined, size: 17),
            label: Text(context.s.print),
          );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: AppTheme.isLight(context)
            ? const Color(0xFFEDF1F5)
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      for (final filter in filters)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: filter,
                        ),
                    ],
                  ),
                ),
                if (print != null) ...<Widget>[
                  const SizedBox(width: 12),
                  print,
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < filters.length; index++) ...<Widget>[
                if (index > 0) const SizedBox(height: 8),
                filters[index],
              ],
              if (print != null) ...<Widget>[
                if (hasFilters) const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerEnd, child: print),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Loading / error / empty shell around a single report body.
class ReportAsyncSection extends StatelessWidget {
  const ReportAsyncSection({
    super.key,
    required this.loading,
    required this.error,
    required this.isEmpty,
    required this.emptyTitle,
    required this.onRetry,
    required this.children,
    this.header,
    this.emptyIcon = Icons.insights_outlined,
  });

  final bool loading;
  final String? error;
  final bool isEmpty;
  final String emptyTitle;
  final Future<void> Function() onRetry;
  final List<Widget> children;
  final Widget? header;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        if (header != null) header!,
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (loading && isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && isEmpty) {
      return ErrorView(message: error!, onRetry: onRetry);
    }
    if (isEmpty) {
      return RefreshIndicator(
        onRefresh: onRetry,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
            EmptyState(icon: emptyIcon, title: emptyTitle),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(10),
        children: children,
      ),
    );
  }
}

/// A single `label — value` row, either plain text or money.
///
/// Rendered as a compact reporting line (label muted, value emphasised) with a
/// hairline separator, the way SAP report totals are displayed.
class ReportKeyValueRow extends StatelessWidget {
  const ReportKeyValueRow({
    super.key,
    required this.label,
    this.value,
    this.amount,
    this.emphasise = false,
  });

  final String label;
  final String? value;
  final double? amount;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: emphasise ? FontWeight.w600 : FontWeight.w400,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: emphasise ? FontWeight.w700 : FontWeight.w600,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(150),
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: labelStyle)),
          if (value != null)
            Text(value!, style: valueStyle)
          else
            MoneyText(amount, style: valueStyle, colorNegative: true),
        ],
      ),
    );
  }
}

/// A [SectionCard] of [ReportKeyValueRow]s.
class ReportTotalsCard extends StatelessWidget {
  const ReportTotalsCard({
    super.key,
    required this.title,
    required this.rows,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      subtitle: subtitle,
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
      child: Column(children: rows),
    );
  }
}

/// A framed table header used above custom report rows.
class ReportTableHeader extends StatelessWidget {
  const ReportTableHeader({super.key, required this.cells});

  /// Cell label plus optional flex/alignment.
  final List<ReportHeaderCell> cells;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.tableHeaderColor(context),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.primary, width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (final cell in cells)
            Expanded(
              flex: cell.flex,
              child: Text(
                cell.label,
                textAlign: cell.align,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.isLight(context)
                      ? AppTheme.textPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ReportHeaderCell {
  const ReportHeaderCell(this.label, {this.flex = 1, this.align = TextAlign.start});

  final String label;
  final int flex;
  final TextAlign align;
}
