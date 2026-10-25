import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../state/reports_controller.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Products that open sales orders still need but that are not on hand, so the
/// shop knows exactly what to purchase to keep the orders moving (نواقص).
class ShortagesReportScreen extends StatelessWidget {
  const ShortagesReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final totals = controller.shortagesTotals;
    return ReportAsyncSection(
      loading: controller.loadingShortages,
      error: controller.shortagesError,
      isEmpty: controller.shortages.isEmpty,
      emptyTitle: s.noShortages,
      emptyIcon: Icons.inventory_2_outlined,
      onRetry: controller.loadShortagesReport,
      header: ReportPrintBar(
        onPrint: () => PrintService.printShortages(context),
      ),
      children: <Widget>[
        SectionCard(
          title: s.totals,
          child: Column(
            children: <Widget>[
              ReportKeyValueRow(
                label: s.shortageProducts,
                value: Formatters.integer(asDouble(totals['products'])),
              ),
              ReportKeyValueRow(
                label: s.requiredQty,
                value: Formatters.integer(asDouble(totals['required'])),
              ),
              ReportKeyValueRow(
                label: s.onHandQty,
                value: Formatters.integer(asDouble(totals['onHand'])),
              ),
              ReportKeyValueRow(
                label: s.shortageQty,
                value: Formatters.integer(asDouble(totals['shortage'])),
              ),
              ReportKeyValueRow(
                label: s.purchaseValue,
                amount: asDouble(totals['purchaseValue']),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.shortages,
          subtitle: s.shortagesHint,
          child: Column(
            children: <Widget>[
              for (final row in controller.shortages) _ShortageTile(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShortageTile extends StatelessWidget {
  const _ShortageTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final sku = asString(row['sku']);
    final orders = (row['orders'] is List)
        ? (row['orders'] as List).whereType<Map>().toList()
        : const <Map>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      asString(row['name'], fallback: sku.isEmpty ? s.product : sku),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  MoneyText(asDouble(row['purchaseValue'])),
                ],
              ),
              const SizedBox(height: 6),
              if ((asStringOrNull(row['category']) ?? '').isNotEmpty)
                Text(
                  '${s.category}: ${asString(row['category'])}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              Text(
                '${s.requiredQty}: ${Formatters.integer(asDouble(row['required']))} · '
                '${s.onHandQty}: ${Formatters.integer(asDouble(row['onHand']))} · '
                '${s.shortageQty}: ${Formatters.integer(asDouble(row['shortage']))}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
              if (orders.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  s.waitingOrders,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                for (final order in orders)
                  Text(
                    '• ${asString(order['orderNumber'])}'
                    '${asStringOrNull(order['customer']) == null ? '' : ' · ${asString(order['customer'])}'}'
                    ' · ${Formatters.integer(asDouble(order['outstanding']))}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
