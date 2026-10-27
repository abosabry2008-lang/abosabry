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
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 18,
              columns: <DataColumn>[
                DataColumn(label: Text(s.product)),
                DataColumn(label: Text(s.code)),
                DataColumn(label: Text(s.shortageQty), numeric: true),
                DataColumn(label: Text(s.purchaseValue), numeric: true),
                DataColumn(label: Text(s.orders), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in controller.shortages)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 280,
                          child: Text(
                            asString(
                              row['name'],
                              fallback: asString(row['sku']).isEmpty
                                  ? s.product
                                  : asString(row['sku']),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(asString(row['sku']))),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(row['shortage'])),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      DataCell(MoneyText(asDouble(row['purchaseValue']))),
                      DataCell(
                        Text(
                          '${(row['orders'] is List) ? (row['orders'] as List).length : 0}',
                          textAlign: TextAlign.end,
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
}
