import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../models/cash_box.dart';
import '../../state/reports_controller.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../shell/navigation.dart';
import '../treasury/box_detail_screen.dart';
import 'report_widgets.dart';

// ---------------------------------------------------------------------------
// Purchases (تقرير المشتريات)
// ---------------------------------------------------------------------------

/// Purchase totals for a period, grouped by day or month.
class PurchasesReportScreen extends StatefulWidget {
  const PurchasesReportScreen({super.key});

  @override
  State<PurchasesReportScreen> createState() => _PurchasesReportScreenState();
}

class _PurchasesReportScreenState extends State<PurchasesReportScreen> {
  DateTime? _from;
  DateTime? _to;
  String _groupBy = 'day';

  void _reload() => context.read<ReportsController>().loadPurchasesReport(
        from: _from,
        to: _to,
        groupBy: _groupBy,
      );

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final totals = asMap(controller.purchasesReport['totals']);
    final series = asMapList(controller.purchasesReport['series']);
    return ReportAsyncSection(
      loading: controller.loadingPurchasesReport,
      error: controller.purchasesReportError,
      isEmpty: series.isEmpty,
      emptyTitle: s.noDataForFilters,
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
          SizedBox(
            width: 190,
            child: AppSelectField<String>(
              label: s.period,
              value: _groupBy,
              options: <SelectOption<String>>[
                SelectOption<String>('day', s.byDay),
                SelectOption<String>('month', s.byMonth),
              ],
              onChanged: (value) {
                setState(() => _groupBy = value ?? 'day');
                _reload();
              },
            ),
          ),
        ],
      ),
      children: <Widget>[
        ReportTotalsCard(
          title: s.totals,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.orders,
              value: Formatters.integer(asDouble(totals['orders'])),
            ),
            ReportKeyValueRow(
              label: s.subtotal,
              amount: asDouble(totals['subtotal']),
            ),
            ReportKeyValueRow(
              label: s.tax,
              amount: asDouble(totals['tax']),
            ),
            ReportKeyValueRow(
              label: s.total,
              amount: asDouble(totals['total']),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.purchasesReport,
          subtitle: s.purchasesReportHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 24,
              columns: <DataColumn>[
                DataColumn(label: Text(s.period)),
                DataColumn(label: Text(s.orders), numeric: true),
                DataColumn(label: Text(s.tax), numeric: true),
                DataColumn(label: Text(s.total), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in series)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 240,
                          child: Text(asString(row['period'])),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(row['orders'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(MoneyText(asDouble(row['tax']))),
                      DataCell(MoneyText(asDouble(row['total']))),
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

// ---------------------------------------------------------------------------
// Sales profit (أرباح المبيعات)
// ---------------------------------------------------------------------------

class ProfitReportScreen extends StatefulWidget {
  const ProfitReportScreen({super.key});

  @override
  State<ProfitReportScreen> createState() => _ProfitReportScreenState();
}

class _ProfitReportScreenState extends State<ProfitReportScreen> {
  DateTime? _from;
  DateTime? _to;

  void _reload() =>
      context.read<ReportsController>().loadProfitReport(from: _from, to: _to);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final totals = asMap(controller.profitReport['totals']);
    final rows = asMapList(controller.profitReport['rows']);
    final profit = asDouble(totals['profit']);
    return ReportAsyncSection(
      loading: controller.loadingProfitReport,
      error: controller.profitReportError,
      isEmpty: rows.isEmpty && controller.profitReport.isEmpty,
      emptyTitle: s.noDataForFilters,
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
              label: s.invoices,
              value: Formatters.integer(asDouble(totals['invoices'])),
            ),
            ReportKeyValueRow(
              label: s.grossSales,
              amount: asDouble(totals['grossRevenue']),
            ),
            ReportKeyValueRow(
              label: s.returns,
              amount: -asDouble(totals['returnsValue']),
            ),
            ReportKeyValueRow(
              label: s.netSales,
              amount: asDouble(totals['revenue']),
            ),
            ReportKeyValueRow(
              label: s.costOfSales,
              amount: asDouble(totals['cost']),
            ),
            ReportKeyValueRow(
              label: s.netProfit,
              value: '${Formatters.money(profit)} '
                  '(${Formatters.money(asDouble(totals['margin']))}%)',
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.salesProfit,
          subtitle: s.salesProfitHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 20,
              columns: <DataColumn>[
                DataColumn(label: Text(s.product)),
                DataColumn(label: Text(s.code)),
                DataColumn(label: Text(s.quantity), numeric: true),
                DataColumn(label: Text(s.costOfSales), numeric: true),
                DataColumn(label: Text(s.netProfit), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in rows.take(200))
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 260,
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
                          Formatters.integer(asDouble(row['quantity'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(MoneyText(asDouble(row['cost']))),
                      DataCell(MoneyText(asDouble(row['profit']))),
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

// ---------------------------------------------------------------------------
// Sales (المبيعات حسب الفترة)
// ---------------------------------------------------------------------------

/// Revenue per day for the period, with a print button.
class SalesReportScreen extends StatelessWidget {
  const SalesReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    final s = context.s;
    return ReportAsyncSection(
      loading: controller.loadingSales,
      error: controller.salesError,
      isEmpty: controller.salesSeries.isEmpty,
      emptyTitle: s.noSalesInPeriod,
      onRetry: () => controller.loadSales(groupBy: 'day'),
      header: ReportPrintBar(
        onPrint: () => PrintService.printSalesReport(context, groupBy: 'day'),
      ),
      children: <Widget>[
        SectionCard(
          title: s.salesByDay,
          subtitle: s.revenuePerDay,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 24,
              columns: <DataColumn>[
                DataColumn(label: Text(s.period)),
                DataColumn(label: Text(s.quantity), numeric: true),
                DataColumn(label: Text(s.revenue), numeric: true),
              ],
              rows: <DataRow>[
                for (final point in controller.salesSeries)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 240,
                          child: Text(point.label),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(point.quantity),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(MoneyText(point.value)),
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

// ---------------------------------------------------------------------------
// Tax report (تقرير الضريبة)
// ---------------------------------------------------------------------------

/// Output tax on sales minus input tax on purchases, with a monthly series.
class TaxReportScreen extends StatefulWidget {
  const TaxReportScreen({super.key});

  @override
  State<TaxReportScreen> createState() => _TaxReportScreenState();
}

class _TaxReportScreenState extends State<TaxReportScreen> {
  DateTime? _from;
  DateTime? _to;

  void _reload() =>
      context.read<ReportsController>().loadTaxReport(from: _from, to: _to);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final totals = asMap(controller.taxReport['totals']);
    final series = asMapList(controller.taxReport['series']);
    return ReportAsyncSection(
      loading: controller.loadingTaxReport,
      error: controller.taxReportError,
      isEmpty: controller.taxReport.isEmpty,
      emptyTitle: s.noDataForFilters,
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
              label: s.taxableSales,
              amount: asDouble(totals['taxableSales']),
            ),
            ReportKeyValueRow(
              label: s.outputTax,
              amount: asDouble(totals['salesTax']),
            ),
            ReportKeyValueRow(
              label: s.taxablePurchases,
              amount: asDouble(totals['taxablePurchases']),
            ),
            ReportKeyValueRow(
              label: s.inputTax,
              amount: asDouble(totals['purchaseTax']),
            ),
            ReportKeyValueRow(
              label: s.netTax,
              amount: asDouble(totals['netTax']),
            ),
          ],
        ),
        if (series.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          SectionCard(
            title: s.period,
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columnSpacing: 24,
                columns: <DataColumn>[
                  DataColumn(label: Text(s.period)),
                  DataColumn(label: Text(s.outputTax), numeric: true),
                  DataColumn(label: Text(s.inputTax), numeric: true),
                  DataColumn(label: Text(s.netTax), numeric: true),
                ],
                rows: <DataRow>[
                  for (final row in series)
                    DataRow(
                      cells: <DataCell>[
                        DataCell(
                          SizedBox(
                            width: 200,
                            child: Text(asString(row['period'])),
                          ),
                        ),
                        DataCell(MoneyText(asDouble(row['salesTax']))),
                        DataCell(MoneyText(asDouble(row['purchaseTax']))),
                        DataCell(MoneyText(asDouble(row['netTax']))),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Aging (أعمار الديون)
// ---------------------------------------------------------------------------

/// Outstanding balances split by age. `side` is `receivable` or `payable`.
class AgingReportScreen extends StatefulWidget {
  const AgingReportScreen({super.key, required this.side});

  final String side;

  @override
  State<AgingReportScreen> createState() => _AgingReportScreenState();
}

class _AgingReportScreenState extends State<AgingReportScreen> {
  DateTime? _asOf;

  bool get _receivable => widget.side == 'receivable';

  void _reload() => _receivable
      ? context.read<ReportsController>().loadReceivablesAging(asOf: _asOf)
      : context.read<ReportsController>().loadPayablesAging(asOf: _asOf);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final data = _receivable
        ? controller.receivablesAging
        : controller.payablesAging;
    final totals = asMap(data['totals']);
    final rows = asMapList(data['rows']);
    final title = _receivable ? s.receivablesAging : s.payablesAging;
    final hint = _receivable ? s.receivablesAgingHint : s.payablesAgingHint;

    return ReportAsyncSection(
      loading: _receivable
          ? controller.loadingReceivablesAging
          : controller.loadingPayablesAging,
      error: _receivable
          ? controller.receivablesAgingError
          : controller.payablesAgingError,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noOutstandingBalances,
      emptyIcon: Icons.hourglass_bottom_outlined,
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
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.notYetDue,
              amount: asDouble(totals['current']),
            ),
            ReportKeyValueRow(
              label: s.days1To30,
              amount: asDouble(totals['d1_30']),
            ),
            ReportKeyValueRow(
              label: s.days31To60,
              amount: asDouble(totals['d31_60']),
            ),
            ReportKeyValueRow(
              label: s.days61To90,
              amount: asDouble(totals['d61_90']),
            ),
            ReportKeyValueRow(
              label: s.over90Days,
              amount: asDouble(totals['d90_plus']),
            ),
            const Divider(),
            ReportKeyValueRow(
              label: s.total,
              amount: asDouble(totals['total']),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: title,
          subtitle: hint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 18,
              columns: <DataColumn>[
                DataColumn(label: Text(_receivable ? s.customer : s.supplier)),
                DataColumn(label: Text(s.notYetDue), numeric: true),
                DataColumn(label: Text(s.days1To30), numeric: true),
                DataColumn(label: Text(s.days31To60), numeric: true),
                DataColumn(label: Text(s.days61To90), numeric: true),
                DataColumn(label: Text(s.over90Days), numeric: true),
                DataColumn(label: Text(s.total), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 230,
                          child: Text(
                            asString(
                              row['name'],
                              fallback: _receivable ? s.customer : s.supplier,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(MoneyText(asDouble(row['current']))),
                      DataCell(MoneyText(asDouble(row['d1_30']))),
                      DataCell(MoneyText(asDouble(row['d31_60']))),
                      DataCell(MoneyText(asDouble(row['d61_90']))),
                      DataCell(MoneyText(asDouble(row['d90_plus']))),
                      DataCell(
                        MoneyText(
                          asDouble(row['total']),
                          colorNegative: true,
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
}

// ---------------------------------------------------------------------------
// Low stock (أصناف منخفضة المخزون)
// ---------------------------------------------------------------------------

class LowStockReportScreen extends StatelessWidget {
  const LowStockReportScreen({super.key});

  Future<void> _reload(BuildContext context) =>
      context.read<ReportsController>().loadLowStockReport();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final rows = controller.lowStock;
    return ReportAsyncSection(
      loading: controller.loadingLowStock,
      error: controller.lowStockError,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noDataForFilters,
      emptyIcon: Icons.inventory_2_outlined,
      onRetry: () => _reload(context),
      children: <Widget>[
        SectionCard(
          title: s.lowStockItems,
          subtitle: s.stockBalanceHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 18,
              columns: <DataColumn>[
                DataColumn(label: Text(s.product)),
                DataColumn(label: Text(s.code)),
                DataColumn(label: Text(s.quantity), numeric: true),
                DataColumn(label: Text(s.shortageQty), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in rows)
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
                          Formatters.integer(asDouble(row['quantity'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(
                        Text(
                          '−${Formatters.integer(asDouble(row['shortage']))}',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
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

// ---------------------------------------------------------------------------
// Cash boxes (أرصدة الخزائن)
// ---------------------------------------------------------------------------

/// Opening balance and current balance of every cash box; tap a box for its
/// statement of account.
class BoxBalancesReportScreen extends StatelessWidget {
  const BoxBalancesReportScreen({super.key});

  Future<void> _reload(BuildContext context) =>
      context.read<ReportsController>().loadBoxes();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final boxes = controller.boxes;
    final total =
        boxes.fold<double>(0, (sum, box) => sum + box.balance);
    return ReportAsyncSection(
      loading: controller.loadingBoxes,
      error: controller.boxesError,
      isEmpty: boxes.isEmpty,
      emptyTitle: s.noDataForFilters,
      emptyIcon: Icons.account_balance_wallet_outlined,
      onRetry: () => _reload(context),
      children: <Widget>[
        ReportTotalsCard(
          title: s.boxBalances,
          subtitle: s.boxBalancesHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.boxCountLabel('${boxes.length}'),
              value: Formatters.integer(boxes.length),
            ),
            ReportKeyValueRow(label: s.total, amount: total),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.cashBoxes,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 18,
              columns: <DataColumn>[
                DataColumn(label: Text(s.cashBox)),
                DataColumn(label: Text(s.code)),
                DataColumn(label: Text(s.type)),
                DataColumn(label: Text(s.openingBalance), numeric: true),
                DataColumn(label: Text(s.balance), numeric: true),
              ],
              rows: <DataRow>[
                for (final box in boxes)
                  DataRow(
                    onSelectChanged: (_) => _open(context, box),
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(box.name, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      DataCell(Text(box.code)),
                      DataCell(
                        Text(box.isMain ? s.mainBox : s.subBox),
                      ),
                      DataCell(MoneyText(box.openingBalance)),
                      DataCell(
                        MoneyText(
                          box.balance,
                          colorNegative: true,
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

  void _open(BuildContext context, CashBox box) {
    pushScreen<void>(
      context,
      box.name,
      BoxDetailScreen(boxId: box.id, initialBox: box),
    );
  }
}
