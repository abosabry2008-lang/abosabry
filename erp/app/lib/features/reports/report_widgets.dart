import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';

/// Print button aligned to the end of the row.
class ReportPrintBar extends StatelessWidget {
  const ReportPrintBar({super.key, required this.onPrint});

  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: <Widget>[
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined),
            label: Text(context.s.print),
          ),
        ],
      ),
    );
  }
}

/// A print bar plus an optional row of filter controls.
class ReportHeader extends StatelessWidget {
  const ReportHeader({super.key, this.onPrint, this.filters = const <Widget>[]});

  /// When `null` no print button is shown.
  final VoidCallback? onPrint;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (onPrint != null) ReportPrintBar(onPrint: onPrint!),
        if (filters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: filters,
            ),
          ),
      ],
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
        padding: const EdgeInsets.all(12),
        children: children,
      ),
    );
  }
}

/// A single `label — value` row, either plain text or money.
class ReportKeyValueRow extends StatelessWidget {
  const ReportKeyValueRow({
    super.key,
    required this.label,
    this.value,
    this.amount,
  });

  final String label;
  final String? value;
  final double? amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          if (value != null)
            Text(value!, style: theme.textTheme.bodyMedium)
          else
            MoneyText(amount, style: theme.textTheme.bodyMedium),
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
      child: Column(children: rows),
    );
  }
}
