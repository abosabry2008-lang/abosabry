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
import 'reports_screen.dart';

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
          child: Column(
            children: <Widget>[
              for (final row in series) _SeriesRow(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeriesRow extends StatelessWidget {
  const _SeriesRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final period = asString(row['period']);
    final orders = Formatters.integer(asDouble(row['orders']));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(period, style: theme.textTheme.bodyMedium),
          ),
          Text(
            '$orders · ${s.tax} ${Formatters.money(asDouble(row['tax']))} · ',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          MoneyText(asDouble(row['total']), style: theme.textTheme.bodyMedium),
        ],
      ),
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
              label: s.revenue,
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
          child: Column(
            children: <Widget>[
              for (final row in rows.take(200)) _ProfitRow(row: row),
            ],
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
          child: Column(
            children: <Widget>[
              for (final point in controller.salesSeries)
                SalesSeriesRow(point: point),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfitRow extends StatelessWidget {
  const _ProfitRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final sku = asString(row['sku']);
    final quantity = Formatters.integer(asDouble(row['quantity']));
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        asString(row['name'], fallback: sku.isEmpty ? s.product : sku),
      ),
      subtitle: Text(
        '$sku · ${s.quantity}: $quantity · '
        '${s.costOfSales}: ${Formatters.money(asDouble(row['cost']))}',
      ),
      trailing: MoneyText(asDouble(row['profit'])),
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
            child: Column(
              children: <Widget>[
                for (final row in series) _TaxRow(row: row),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TaxRow extends StatelessWidget {
  const _TaxRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  asString(row['period']),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              MoneyText(
                asDouble(row['netTax']),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${s.outputTax}: ${Formatters.money(asDouble(row['salesTax']))}'
                  ' · ${s.inputTax}: ${Formatters.money(asDouble(row['purchaseTax']))}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ],
          ),
        ],
      ),
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
          child: Column(
            children: <Widget>[
              for (final row in rows) _AgingRow(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _AgingRow extends StatelessWidget {
  const _AgingRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final parts = <String>[];
    void add(String label, double value) {
      if (value != 0) parts.add('$label ${Formatters.money(value)}');
    }

    add(s.notYetDue, asDouble(row['current']));
    add(s.days1To30, asDouble(row['d1_30']));
    add(s.days31To60, asDouble(row['d31_60']));
    add(s.days61To90, asDouble(row['d61_90']));
    add(s.over90Days, asDouble(row['d90_plus']));

    final phone = asStringOrNull(row['phone']);
    final subtitle = parts.isEmpty ? s.notYetDue : parts.join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(asString(row['name'], fallback: s.customer)),
      subtitle: Text(
        phone == null ? subtitle : '$phone · $subtitle',
        style: theme.textTheme.bodySmall,
      ),
      trailing: MoneyText(asDouble(row['total']), colorNegative: true),
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
          child: Column(
            children: <Widget>[
              for (final row in rows) _LowStockRow(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final sku = asString(row['sku']);
    final quantity = Formatters.integer(asDouble(row['quantity']));
    final shortage = Formatters.integer(asDouble(row['shortage']));
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        asString(row['name'], fallback: sku.isEmpty ? s.product : sku),
      ),
      subtitle: Text('$sku · ${s.quantity}: $quantity'),
      trailing: Text(
        '−$shortage',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      ),
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
          child: Column(
            children: <Widget>[
              for (final box in boxes)
                _BoxRow(box: box, onTap: () => _open(context, box)),
            ],
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
  }}

class _BoxRow extends StatelessWidget {
  const _BoxRow({required this.box, required this.onTap});

  final CashBox box;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        box.isMain ? Icons.account_balance_outlined : Icons.savings_outlined,
      ),
      title: Text(box.name),
      subtitle: Text(
        '${box.code} · ${box.isMain ? s.mainBox : s.subBox} · '
        '${s.openingShort}: ${Formatters.money(box.openingBalance)}',
      ),
      trailing: MoneyText(
        box.balance,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      onTap: onTap,
    );
  }
}
