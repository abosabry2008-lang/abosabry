import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../state/reports_controller.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Safely renders an ISO date string from the API.
String _formatDate(String value) {
  final parsed = DateTime.tryParse(value);
  return Formatters.date(parsed);
}

/// The order-fulfilment board (المتاح والمطلوب): one card per open sales order
/// showing, line by line, what is on hand versus what still has to be purchased
/// before the order can be finished.
class OrderFulfilmentReportScreen extends StatelessWidget {
  const OrderFulfilmentReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final totals = controller.orderFulfilmentTotals;
    return ReportAsyncSection(
      loading: controller.loadingOrderFulfilment,
      error: controller.orderFulfilmentError,
      isEmpty: controller.orderFulfilment.isEmpty,
      emptyTitle: s.noOpenOrders,
      emptyIcon: Icons.assignment_turned_in_outlined,
      onRetry: controller.loadOrderFulfilmentReport,
      header: ReportPrintBar(
        onPrint: () => PrintService.printOrderFulfilment(context),
      ),
      children: <Widget>[
        SectionCard(
          title: s.totals,
          child: Column(
            children: <Widget>[
              ReportKeyValueRow(
                label: s.orders,
                value: Formatters.integer(asDouble(totals['orders'])),
              ),
              ReportKeyValueRow(
                label: s.requiredQty,
                value: Formatters.integer(asDouble(totals['required'])),
              ),
              ReportKeyValueRow(
                label: s.availableQty,
                value: Formatters.integer(asDouble(totals['available'])),
              ),
              ReportKeyValueRow(
                label: s.shortageQty,
                value: Formatters.integer(asDouble(totals['shortage'])),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.orderFulfilmentTitle,
          subtitle: s.orderFulfilmentHint,
          child: Column(
            children: <Widget>[
              for (final row in controller.orderFulfilment)
                _OrderTile(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final ready = row['fullyAvailable'] == true;
    final lines = (row['lines'] is List)
        ? (row['lines'] as List).whereType<Map>().map(asMap).toList()
        : const <Map<String, dynamic>>[];
    final color = ready
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      asString(row['orderNumber']),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      ready ? s.fullyAvailable : s.needsPurchasing,
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                <String>[
                  if (asStringOrNull(row['customer']) != null)
                    asString(row['customer']),
                  _formatDate(asString(row['orderDate'])),
                  asString(row['warehouse']),
                ].join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 8),
              for (final line in lines) _LineRow(line: line),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final Map<String, dynamic> line;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final short = asDouble(line['shortage']);
    final color = short > 0 ? theme.colorScheme.error : theme.colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              <String>[
                asString(line['name']),
                if (asStringOrNull(line['sku']) != null)
                  '(${asString(line['sku'])})',
              ].join(' '),
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Text(
              '${s.requiredQty}: ${Formatters.integer(asDouble(line['required']))} · '
              '${s.availableQty}: ${Formatters.integer(asDouble(line['available']))} · '
              '${s.shortageQty}: ${Formatters.integer(short)}',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
