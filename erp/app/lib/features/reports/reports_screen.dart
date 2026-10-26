import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/sales_point.dart';
import '../../models/warehouse.dart';
import '../../state/reports_controller.dart';
import '../../state/salespeople_controller.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../customers/customer_statement_screen.dart';
import '../shell/navigation.dart';
import '../suppliers/supplier_statement_screen.dart';
import 'dormant_customers_screen.dart';
import 'extra_report_screen.dart';
import 'financial_reports_screen.dart';
import 'general_ledger_screen.dart';
import 'investment_equation_screen.dart';
import 'expense_report_screen.dart';
import 'item_movement_screen.dart';
import 'operations_reports_screen.dart';
import 'price_list_screen.dart';
import 'order_fulfilment_report_screen.dart';
import 'report_widgets.dart';
import 'salespeople_reports_screen.dart';
import 'salesperson_daily_invoices_screen.dart';
import 'salesperson_customer_debt_screen.dart';
import 'shortages_report_screen.dart';
import 'statement_hub_screen.dart';

/// Report hub: a search box plus grouped, responsive report cards.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = context.watch<Session>();
    final groups = _groups(context, session);
    final query = _query.trim().toLowerCase();

    final visible = <_ReportGroup>[];
    for (final group in groups) {
      if (query.isNotEmpty &&
          !group.title.toLowerCase().contains(query) &&
          !group.description.toLowerCase().contains(query)) {
        final matches = group.reports
            .where((report) => report.title.toLowerCase().contains(query))
            .toList();
        if (matches.isEmpty) continue;
        visible.add(group.copyWith(reports: matches));
      } else {
        visible.add(group);
      }
    }
    final reportCount =
        visible.fold<int>(0, (sum, group) => sum + group.reports.length);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        SectionCard(
          title: s.reports,
          subtitle: s.reportTreeHint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppSearchField(
                hintText: s.reportSearchHint,
                initialValue: _query,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.grid_view_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.reportCountLabel('$reportCount'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: <Widget>[
                Icon(
                  Icons.search_off,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(s.noReportsMatch),
              ],
            ),
          ),
        for (final group in visible) ...<Widget>[
          const SizedBox(height: 18),
          _GroupHeading(group: group),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 980
                  ? 3
                  : constraints.maxWidth >= 620
                      ? 2
                      : 1;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: group.reports
                    .map(
                      (report) => SizedBox(
                        width: width,
                        child: _ReportCard(report: report),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  List<_ReportGroup> _groups(BuildContext context, Session session) {
    final s = context.s;
    return <_ReportGroup>[
      _ReportGroup(
        icon: Icons.point_of_sale_outlined,
        title: s.sales,
        description: s.salesReportsDesc,
        reports: <_ReportSpec>[
          _ReportSpec(
            icon: Icons.show_chart_outlined,
            title: s.sales,
            onOpen: (controller) => controller.loadSales(groupBy: 'day'),
            builder: (_) => const SalesReportScreen(),
          ),
          _ReportSpec(
            icon: Icons.people_alt_outlined,
            title: s.salesByCustomer,
            builder: (_) => ExtraReportScreen(
              title: s.salesByCustomer,
              path: '/reports/sales-by-customer',
              columns: <ReportColumn>[
                ReportColumn('customerName', s.customer),
                ReportColumn('code', s.code),
                ReportColumn('invoices', s.invoices,
                    value: ReportValue.integer),
                ReportColumn('total', s.total, value: ReportValue.money),
                ReportColumn('paid', s.paid, value: ReportValue.money),
                ReportColumn('balance', s.balance, value: ReportValue.money),
                if (session.canViewProfit) ...<ReportColumn>[
                  ReportColumn('cost', s.costOfSales, value: ReportValue.money),
                  ReportColumn('profit', s.netProfit, value: ReportValue.money),
                ],
              ],
              totals: <ReportTotal>[
                ReportTotal('customers', s.customers, money: false),
                ReportTotal('invoices', s.invoices, money: false),
                ReportTotal('total', s.total),
                ReportTotal('paid', s.paid),
                ReportTotal('balance', s.balance),
                if (session.canViewProfit) ...<ReportTotal>[
                  ReportTotal('cost', s.costOfSales),
                  ReportTotal('profit', s.netProfit),
                ],
              ],
            ),
          ),
          _ReportSpec(
            icon: Icons.category_outlined,
            title: s.salesByCategory,
            builder: (_) => ExtraReportScreen(
              title: s.salesByCategory,
              path: '/reports/sales-by-category',
              columns: <ReportColumn>[
                ReportColumn('categoryName', s.category),
                ReportColumn('quantity', s.quantity, value: ReportValue.integer),
                ReportColumn('revenue', s.revenue, value: ReportValue.money),
                if (session.canViewProfit) ...<ReportColumn>[
                  ReportColumn('cost', s.costOfSales, value: ReportValue.money),
                  ReportColumn('profit', s.netProfit, value: ReportValue.money),
                ],
              ],
              totals: <ReportTotal>[
                ReportTotal('categories', s.categories, money: false),
                ReportTotal('quantity', s.quantity, money: false),
                ReportTotal('revenue', s.revenue),
                if (session.canViewProfit) ...<ReportTotal>[
                  ReportTotal('cost', s.costOfSales),
                  ReportTotal('profit', s.netProfit),
                ],
              ],
            ),
          ),
          _ReportSpec(
            icon: Icons.leaderboard_outlined,
            title: s.topProducts,
            onOpen: (controller) => controller.loadTopProducts(),
            builder: (_) => const _TopProductsTab(),
          ),
          if (session.canViewProfit)
          _ReportSpec(
            icon: Icons.savings_outlined,
            title: s.salesProfit,
            onOpen: (controller) => controller.loadProfitReport(),
            builder: (_) => const ProfitReportScreen(),
          ),
          _ReportSpec(
            icon: Icons.assignment_return_outlined,
            title: s.returnsReport,
            builder: (_) => ExtraReportScreen(
              title: s.returnsReport,
              path: '/reports/returns',
              typeFilter: true,
              columns: <ReportColumn>[
                ReportColumn('number', s.numberLabel),
                ReportColumn('date', s.date, value: ReportValue.date),
                ReportColumn('type', s.returnType, value: ReportValue.status),
                ReportColumn('partyName', s.partner),
                ReportColumn('total', s.total, value: ReportValue.money),
                ReportColumn('status', s.statusWord, value: ReportValue.status),
              ],
              totals: <ReportTotal>[
                ReportTotal('count', s.countLabel, money: false),
                ReportTotal('total', s.total),
                ReportTotal('customerTotal', s.customerReturns),
                ReportTotal('supplierTotal', s.supplierReturns),
              ],
            ),
          ),
          _ReportSpec(
            icon: Icons.support_agent_outlined,
            title: s.receivablesBySalesperson,
            onOpen: (controller) => controller.loadReceivables(),
            builder: (_) => const _ReceivablesTab(),
          ),
          _ReportSpec(
            icon: Icons.production_quantity_limits_outlined,
            title: s.shortages,
            onOpen: (controller) => controller.loadShortagesReport(),
            builder: (_) => const ShortagesReportScreen(),
          ),
          _ReportSpec(
            icon: Icons.assignment_turned_in_outlined,
            title: s.orderFulfilmentTitle,
            onOpen: (controller) => controller.loadOrderFulfilmentReport(),
            builder: (_) => const OrderFulfilmentReportScreen(),
          ),
        ],
      ),
      _ReportGroup(
        icon: Icons.support_agent_outlined,
        title: s.salespeopleReports,
        description: s.salespeopleReportsDesc,
        reports: <_ReportSpec>[
          _ReportSpec(
            icon: Icons.print_outlined,
            title: s.dailyInvoicesPrint,
            builder: (_) => const SalespersonDailyInvoicesScreen(),
          ),
          _ReportSpec(
            icon: Icons.receipt_long_outlined,
            title: s.consolidatedSalesNote,
            onOpen: (controller) => controller.loadConsolidatedSalesNote(),
            builder: (_) => const ConsolidatedSalesNoteScreen(),
          ),
          _ReportSpec(
            icon: Icons.badge_outlined,
            title: s.salesBySalesperson,
            builder: (_) => ExtraReportScreen(
              title: s.salesBySalesperson,
              path: '/reports/sales-by-salesperson',
              columns: <ReportColumn>[
                ReportColumn('salespersonName', s.salesperson),
                ReportColumn('invoices', s.invoices,
                    value: ReportValue.integer),
                ReportColumn('total', s.total, value: ReportValue.money),
                ReportColumn('paid', s.paid, value: ReportValue.money),
                ReportColumn('balance', s.balance, value: ReportValue.money),
              ],
              totals: <ReportTotal>[
                ReportTotal('salespeople', s.salespeopleReports, money: false),
                ReportTotal('invoices', s.invoices, money: false),
                ReportTotal('total', s.total),
                ReportTotal('paid', s.paid),
                ReportTotal('balance', s.balance),
              ],
            ),
          ),
          if (session.canViewProfit)
          _ReportSpec(
            icon: Icons.savings_outlined,
            title: s.profitBySalesperson,
            onOpen: (controller) => controller.loadProfitBySalesperson(),
            builder: (_) => const ProfitBySalespersonScreen(),
          ),
          _ReportSpec(
            icon: Icons.payments_outlined,
            title: s.collectionsBySalesperson,
            onOpen: (controller) => controller.loadCollectionsBySalesperson(),
            builder: (_) => const CollectionsBySalespersonScreen(),
          ),
          _ReportSpec(
            icon: Icons.account_balance_wallet_outlined,
            title: s.salespersonStatement,
            builder: (_) => const SalespersonStatementScreen(),
          ),
          _ReportSpec(
            icon: Icons.table_chart_outlined,
            title: s.salespersonCustomerDebt,
            builder: (_) => const SalespersonCustomerDebtScreen(),
          ),
        ],
      ),
      if (session.can('purchases'))
        _ReportGroup(
          icon: Icons.shopping_cart_outlined,
          title: s.purchases,
          description: s.purchasesReportsDesc,
          reports: <_ReportSpec>[
            _ReportSpec(
              icon: Icons.receipt_long_outlined,
              title: s.purchasesReport,
              onOpen: (controller) =>
                  controller.loadPurchasesReport(groupBy: 'day'),
              builder: (_) => const PurchasesReportScreen(),
            ),
            _ReportSpec(
              icon: Icons.local_shipping_outlined,
              title: s.purchasesBySupplier,
              builder: (_) => ExtraReportScreen(
                title: s.purchasesBySupplier,
                path: '/reports/purchases-by-supplier',
                columns: <ReportColumn>[
                  ReportColumn('supplierName', s.supplier),
                  ReportColumn('orders', s.orders, value: ReportValue.integer),
                  ReportColumn('total', s.total, value: ReportValue.money),
                  ReportColumn('receivedValue', s.received,
                      value: ReportValue.money),
                  ReportColumn('balance', s.balance, value: ReportValue.money),
                ],
                totals: <ReportTotal>[
                  ReportTotal('suppliers', s.suppliers, money: false),
                  ReportTotal('orders', s.orders, money: false),
                  ReportTotal('total', s.total),
                  ReportTotal('receivedValue', s.received),
                  ReportTotal('balance', s.balance),
                ],
              ),
            ),
            _ReportSpec(
              icon: Icons.account_balance_wallet_outlined,
              title: s.supplierPayables,
              onOpen: (controller) => controller.loadSupplierPayables(),
              builder: (_) => const _SupplierPayablesTab(),
            ),
          ],
        ),
      if (session.can('customers'))
        _ReportGroup(
          icon: Icons.people_outline,
          title: s.customers,
          description: s.customersReportsDesc,
          reports: <_ReportSpec>[
            _ReportSpec(
              icon: Icons.account_balance_wallet_outlined,
              title: s.customerBalances,
              onOpen: (controller) => controller.loadCustomerBalances(),
              builder: (_) => const _CustomerBalancesTab(),
            ),
            _ReportSpec(
              icon: Icons.person_off_outlined,
              title: s.dormantCustomers,
              builder: (_) => const DormantCustomersScreen(),
            ),
            _ReportSpec(
              icon: Icons.hourglass_bottom_outlined,
              title: s.receivablesAging,
              onOpen: (controller) => controller.loadReceivablesAging(),
              builder: (_) => const AgingReportScreen(side: 'receivable'),
            ),
            _ReportSpec(
              icon: Icons.list_alt_outlined,
              title: s.customerStatement,
              builder: (_) => const StatementHubScreen(
                startWith: StatementKind.customer,
              ),
            ),
          ],
        ),
      if (session.can('suppliers'))
        _ReportGroup(
          icon: Icons.handshake_outlined,
          title: s.suppliers,
          description: s.suppliersReportsDesc,
          reports: <_ReportSpec>[
            _ReportSpec(
              icon: Icons.account_balance_wallet_outlined,
              title: s.supplierBalances,
              onOpen: (controller) => controller.loadSupplierBalances(),
              builder: (_) => const _SupplierBalancesTab(),
            ),
            _ReportSpec(
              icon: Icons.hourglass_top_outlined,
              title: s.payablesAging,
              onOpen: (controller) => controller.loadPayablesAging(),
              builder: (_) => const AgingReportScreen(side: 'payable'),
            ),
            _ReportSpec(
              icon: Icons.local_shipping_outlined,
              title: s.supplierStatement,
              builder: (_) => const StatementHubScreen(
                startWith: StatementKind.supplier,
              ),
            ),
          ],
        ),
      if (session.can('inventory'))
        _ReportGroup(
          icon: Icons.inventory_2_outlined,
          title: s.inventory,
          description: s.inventoryReportsDesc,
          reports: <_ReportSpec>[
            _ReportSpec(
              icon: Icons.sell_outlined,
              title: s.priceList,
              builder: (_) => const PriceListScreen(),
            ),
            _ReportSpec(
              icon: Icons.price_change_outlined,
              title: s.valuation,
              onOpen: (controller) => controller.loadValuation(),
              builder: (_) => const _ValuationTab(),
            ),
            _ReportSpec(
              icon: Icons.warehouse_outlined,
              title: s.stockBalance,
              onOpen: (controller) => controller.loadStockBalance(),
              builder: (_) => const _StockBalanceTab(),
            ),
            _ReportSpec(
              icon: Icons.timeline_outlined,
              title: s.itemMovement,
              builder: (_) => const ItemMovementScreen(),
            ),
            _ReportSpec(
              icon: Icons.production_quantity_limits_outlined,
              title: s.lowStockItems,
              onOpen: (controller) => controller.loadLowStockReport(),
              builder: (_) => const LowStockReportScreen(),
            ),
            _ReportSpec(
              icon: Icons.hourglass_disabled_outlined,
              title: s.deadStock,
              builder: (_) => ExtraReportScreen(
                title: s.deadStock,
                path: '/reports/dead-stock',
                dateRange: false,
                daysSelector: true,
                columns: <ReportColumn>[
                  ReportColumn('sku', s.code),
                  ReportColumn('name', s.product),
                  ReportColumn('quantity', s.quantity,
                      value: ReportValue.integer),
                  ReportColumn('costValue', s.costValue,
                      value: ReportValue.money),
                  ReportColumn('lastSaleAt', s.lastSale,
                      value: ReportValue.date),
                  ReportColumn('daysSince', s.daysInStock,
                      value: ReportValue.integer),
                ],
                totals: <ReportTotal>[
                  ReportTotal('items', s.countLabel, money: false),
                  ReportTotal('units', s.units, money: false),
                  ReportTotal('costValue', s.costValue),
                  ReportTotal('retailValue', s.retailValue),
                ],
              ),
            ),
          ],
        ),
      if (session.can('treasury'))
        _ReportGroup(
          icon: Icons.account_balance_wallet_outlined,
          title: s.treasury,
          description: s.treasuryReportsDesc,
          reports: <_ReportSpec>[
            _ReportSpec(
              icon: Icons.account_balance_outlined,
              title: s.boxBalances,
              onOpen: (controller) => controller.loadBoxes(),
              builder: (_) => const BoxBalancesReportScreen(),
            ),
            _ReportSpec(
              icon: Icons.waterfall_chart_outlined,
              title: s.cashFlow,
              builder: (_) => ExtraReportScreen(
                title: s.cashFlow,
                path: '/reports/cash-flow',
                columns: <ReportColumn>[
                  ReportColumn('cashBoxName', s.cashBox),
                  ReportColumn('opening', s.openingBalance,
                      value: ReportValue.money),
                  ReportColumn('inTotal', s.inTotal, value: ReportValue.money),
                  ReportColumn('outTotal', s.outTotal,
                      value: ReportValue.money),
                  ReportColumn('net', s.netMovement, value: ReportValue.money),
                  ReportColumn('closing', s.closingBalance,
                      value: ReportValue.money),
                ],
                totals: <ReportTotal>[
                  ReportTotal('boxes', s.cashBoxes, money: false),
                  ReportTotal('opening', s.openingBalance),
                  ReportTotal('inTotal', s.inTotal),
                  ReportTotal('outTotal', s.outTotal),
                  ReportTotal('net', s.netMovement),
                  ReportTotal('closing', s.closingBalance),
                ],
              ),
            ),
            if (session.can('expenses'))
              _ReportSpec(
                icon: Icons.call_made,
                title: s.expenseReport,
                onOpen: (controller) => controller.loadExpenseReport(),
                builder: (_) => const ExpenseReportScreen(),
              ),
            _ReportSpec(
              icon: Icons.credit_card_outlined,
              title: s.paymentsByMethod,
              builder: (_) => ExtraReportScreen(
                title: s.paymentsByMethod,
                path: '/reports/payments-by-method',
                columns: <ReportColumn>[
                  ReportColumn('method', s.paymentMethod,
                      value: ReportValue.status),
                  ReportColumn('count', s.countLabel,
                      value: ReportValue.integer),
                  ReportColumn('inTotal', s.inTotal, value: ReportValue.money),
                  ReportColumn('outTotal', s.outTotal,
                      value: ReportValue.money),
                  ReportColumn('net', s.netMovement, value: ReportValue.money),
                ],
                totals: <ReportTotal>[
                  ReportTotal('count', s.countLabel, money: false),
                  ReportTotal('inTotal', s.inTotal),
                  ReportTotal('outTotal', s.outTotal),
                  ReportTotal('net', s.netMovement),
                ],
              ),
            ),
          ],
        ),
      if (session.can('accounting'))
        _ReportGroup(
          icon: Icons.calculate_outlined,
          title: s.accounting,
          description: s.accountingReportsDesc,
          reports: <_ReportSpec>[
            _ReportSpec(
              icon: Icons.menu_book_outlined,
              title: s.generalLedger,
              builder: (_) => const GeneralLedgerScreen(),
            ),
            _ReportSpec(
              icon: Icons.account_balance_wallet_outlined,
              title: s.investmentEquation,
              builder: (_) => const InvestmentEquationScreen(),
            ),
            _ReportSpec(
              icon: Icons.balance_outlined,
              title: s.trialBalance,
              onOpen: (controller) => controller.loadTrialBalance(),
              builder: (_) => const TrialBalanceReportScreen(),
            ),
            _ReportSpec(
              icon: Icons.trending_up_outlined,
              title: s.incomeStatement,
              onOpen: (controller) => controller.loadIncomeStatement(),
              builder: (_) => const IncomeStatementReportScreen(),
            ),
            _ReportSpec(
              icon: Icons.account_balance_outlined,
              title: s.balanceSheet,
              onOpen: (controller) => controller.loadBalanceSheet(),
              builder: (_) => const BalanceSheetReportScreen(),
            ),
            _ReportSpec(
              icon: Icons.receipt_outlined,
              title: s.taxReport,
              onOpen: (controller) => controller.loadTaxReport(),
              builder: (_) => const TaxReportScreen(),
            ),
          ],
        ),
    ];
  }
}

class _ReportGroup {
  const _ReportGroup({
    required this.icon,
    required this.title,
    required this.description,
    required this.reports,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<_ReportSpec> reports;

  _ReportGroup copyWith({List<_ReportSpec>? reports}) => _ReportGroup(
        icon: icon,
        title: title,
        description: description,
        reports: reports ?? this.reports,
      );
}

class _ReportSpec {
  const _ReportSpec({
    required this.icon,
    required this.title,
    required this.builder,
    this.onOpen,
  });

  final IconData icon;
  final String title;
  final WidgetBuilder builder;
  final Future<void> Function(ReportsController controller)? onOpen;
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.group});

  final _ReportGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppTheme.sectionHeaderColor(context),
        borderRadius: BorderRadius.circular(4),
        border: BorderDirectional(
          start: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(group.icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (group.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      group.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final _ReportSpec report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final controller = context.read<ReportsController>();
          final onOpen = report.onOpen;
          if (onOpen != null) unawaited(onOpen(controller));
          pushScreen<void>(context, report.title, report.builder(context));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: scheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(report.icon, size: 17, color: scheme.primary),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  report.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopProductsTab extends StatelessWidget {
  const _TopProductsTab();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    final s = context.s;
    return ReportAsyncSection(
      loading: controller.loadingTopProducts,
      error: controller.topProductsError,
      isEmpty: controller.topProducts.isEmpty,
      emptyTitle: s.noProductSalesYet,
      onRetry: controller.loadTopProducts,
      header: ReportPrintBar(
        onPrint: () => PrintService.printTopProducts(context, limit: 10),
      ),
      children: <Widget>[
        SectionCard(
          title: s.topProducts,
          subtitle: s.last30Days,
          child: Column(
            children: <Widget>[
              for (final point in controller.topProducts)
                SalesSeriesRow(point: point, showQuantity: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _ValuationTab extends StatelessWidget {
  const _ValuationTab();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final valuation = controller.valuation;
    final totals = valuation['totals'];
    final rows = (valuation['rows'] is List)
        ? (valuation['rows'] as List)
            .whereType<Map>()
            .map((row) => row.cast<String, dynamic>())
            .toList()
        : <Map<String, dynamic>>[];
    return ReportAsyncSection(
      loading: controller.loadingValuation,
      error: controller.valuationError,
      isEmpty: rows.isEmpty && valuation.isEmpty,
      emptyTitle: s.noStockToValuate,
      onRetry: controller.loadValuation,
      header: ReportPrintBar(
        onPrint: () => PrintService.printInventoryValuation(context),
      ),
      children: <Widget>[
        if (totals is Map)
          SectionCard(
            title: s.totals,
            child: Column(
              children: <Widget>[
                ReportKeyValueRow(
                  label: s.stockLines,
                  value: Formatters.integer(asDouble(totals['lines'])),
                ),
                ReportKeyValueRow(
                  label: s.units,
                  value: Formatters.integer(asDouble(totals['units'])),
                ),
                ReportKeyValueRow(
                  label: s.costValue,
                  amount: asDouble(totals['costValue']),
                ),
                ReportKeyValueRow(
                  label: s.retailValue,
                  amount: asDouble(totals['retailValue']),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.valuationByLine,
          subtitle: s.lineCount(rows.length),
          child: Column(
            children: <Widget>[
              for (final row in rows.take(100))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${row['name'] ?? row['sku'] ?? s.itemLower}'),
                  subtitle: Text(
                    '${s.lineWithQty(
                      asString(row['sku']),
                      Formatters.integer(asDouble(row['quantity'])),
                    )}'
                    '${asStringOrNull(row['category']) == null ? '' : ' · ${asString(row['category'])}'}',
                  ),
                  trailing: MoneyText(asDouble(row['costValue'])),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerBalancesTab extends StatefulWidget {
  const _CustomerBalancesTab();

  @override
  State<_CustomerBalancesTab> createState() => _CustomerBalancesTabState();
}

class _CustomerBalancesTabState extends State<_CustomerBalancesTab> {
  String? _salespersonId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalespeopleController>().ensureLoaded();
    });
  }

  Future<void> _reload() => context
      .read<ReportsController>()
      .loadCustomerBalances(salespersonId: _salespersonId);

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    final salespeople = context.watch<SalespeopleController>().salespeople;
    final s = context.s;
    return ReportAsyncSection(
      loading: controller.loadingCustomerBalances,
      error: controller.customerBalancesError,
      isEmpty: controller.customerBalances.isEmpty,
      emptyTitle: s.noOutstandingBalances,
      onRetry: _reload,
      header: ReportHeader(
        onPrint: () => PrintService.printCustomerBalances(
          context,
          salespersonId: _salespersonId,
        ),
        filters: <Widget>[
          AppSelectField<String?>(
            label: s.salesperson,
            value: _salespersonId,
            prefixIcon: Icons.support_agent_outlined,
            options: <SelectOption<String?>>[
              SelectOption<String?>(null, s.allSalespeople),
              for (final person in salespeople)
                SelectOption<String?>(person.id, person.name),
            ],
            onChanged: (value) {
              setState(() => _salespersonId = value);
              _reload();
            },
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.customerBalances,
          subtitle: s.customerCountLabel('${controller.customerBalances.length}'),
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 20,
              columns: <DataColumn>[
                DataColumn(label: Text(s.customer)),
                DataColumn(label: Text(s.invoices), numeric: true),
                DataColumn(label: Text(s.balance), numeric: true),
                DataColumn(label: Text(s.accountStatement)),
              ],
              rows: <DataRow>[
                for (final row in controller.customerBalances)
                  _customerBalanceRow(context, row),
              ],
            ),
          ),
        ),
      ],
    );
  }

  DataRow _customerBalanceRow(
    BuildContext context,
    Map<String, dynamic> row,
  ) {
    final s = context.s;
    final name = asString(row['name'], fallback: s.customer);
    final id = asStringOrNull(row['id']) ?? asStringOrNull(row['customerId']);
    return DataRow(
      onSelectChanged: id == null
          ? null
          : (_) => openCustomerStatement(
                context,
                customerId: id,
                customerName: name,
              ),
      cells: <DataCell>[
        DataCell(SizedBox(width: 240, child: Text(name))),
        DataCell(Text(Formatters.integer(asDouble(row['invoices'])))),
        DataCell(MoneyText(asDouble(row['balance']), colorNegative: true)),
        DataCell(
          Icon(
            Icons.list_alt_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _SupplierBalancesTab extends StatelessWidget {
  const _SupplierBalancesTab();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    final s = context.s;
    return ReportAsyncSection(
      loading: controller.loadingSupplierBalances,
      error: controller.supplierBalancesError,
      isEmpty: controller.supplierBalances.isEmpty,
      emptyTitle: s.noOutstandingBalances,
      onRetry: controller.loadSupplierBalances,
      children: <Widget>[
        SectionCard(
          title: s.supplierBalances,
          subtitle: s.supplierCountLabel('${controller.supplierBalances.length}'),
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 20,
              columns: <DataColumn>[
                DataColumn(label: Text(s.supplier)),
                DataColumn(label: Text(s.orders), numeric: true),
                DataColumn(label: Text(s.balance), numeric: true),
                DataColumn(label: Text(s.accountStatement)),
              ],
              rows: <DataRow>[
                for (final row in controller.supplierBalances)
                  _supplierBalanceRow(context, row),
              ],
            ),
          ),
        ),
      ],
    );
  }

  DataRow _supplierBalanceRow(
    BuildContext context,
    Map<String, dynamic> row,
  ) {
    final s = context.s;
    final name = asString(row['name'], fallback: s.supplier);
    final id = asStringOrNull(row['id']) ?? asStringOrNull(row['supplierId']);
    return DataRow(
      onSelectChanged: id == null
          ? null
          : (_) => openSupplierStatement(
                context,
                supplierId: id,
                supplierName: name,
              ),
      cells: <DataCell>[
        DataCell(SizedBox(width: 240, child: Text(name))),
        DataCell(
          Text(
            Formatters.integer(
              asDouble(row['purchaseOrders'] ?? row['invoices']),
            ),
          ),
        ),
        DataCell(MoneyText(asDouble(row['balance']), colorNegative: true)),
        DataCell(
          Icon(
            Icons.list_alt_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _ReceivablesTab extends StatefulWidget {
  const _ReceivablesTab();

  @override
  State<_ReceivablesTab> createState() => _ReceivablesTabState();
}

class _ReceivablesTabState extends State<_ReceivablesTab> {
  DateTime? _from;
  DateTime? _to;
  String? _salespersonId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalespeopleController>().ensureLoaded();
    });
  }

  Future<void> _reload() => context.read<ReportsController>().loadReceivables(
        from: _from,
        to: _to,
        userId: _salespersonId,
      );

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final salespeople = context.watch<SalespeopleController>().salespeople;
    final totals = controller.receivablesTotals;
    return ReportAsyncSection(
      loading: controller.loadingReceivables,
      error: controller.receivablesError,
      isEmpty: controller.receivables.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: _reload,
      header: ReportHeader(
        onPrint: () => PrintService.printReceivablesBySalesperson(
          context,
          from: _from,
          to: _to,
          userId: _salespersonId,
        ),
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
          const SizedBox(height: 10),
          AppSelectField<String?>(
            label: s.salesperson,
            value: _salespersonId,
            prefixIcon: Icons.support_agent_outlined,
            options: <SelectOption<String?>>[
              SelectOption<String?>(null, s.allSalespeople),
              for (final person in salespeople)
                SelectOption<String?>(person.id, person.name),
            ],
            onChanged: (value) {
              setState(() => _salespersonId = value);
              _reload();
            },
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.totals,
          child: Column(
            children: <Widget>[
              ReportKeyValueRow(
                label: s.previousBalanceLabel,
                amount: asDouble(totals['openingBalance']),
              ),
              ReportKeyValueRow(
                label: s.periodBalance,
                amount: asDouble(totals['periodBalance']),
              ),
              ReportKeyValueRow(
                label: s.total,
                amount: asDouble(totals['total']),
              ),
              ReportKeyValueRow(
                label: s.paid,
                amount: asDouble(totals['paid']),
              ),
              ReportKeyValueRow(
                label: s.balance,
                amount: asDouble(totals['balance']),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.receivablesBySalesperson,
          subtitle: s.receivablesBySalespersonHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 20,
              columns: <DataColumn>[
                DataColumn(label: Text(s.customer)),
                DataColumn(label: Text(s.salesperson)),
                DataColumn(label: Text(s.invoices), numeric: true),
                DataColumn(label: Text(s.previousBalanceLabel), numeric: true),
                DataColumn(label: Text(s.periodBalance), numeric: true),
                DataColumn(label: Text(s.balance), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in controller.receivables)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(
                            asString(row['customer'], fallback: s.customer),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          asStringOrNull(row['salesperson']) ?? s.unassigned,
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(row['invoices'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(
                        MoneyText(asDouble(row['openingBalance'])),
                      ),
                      DataCell(MoneyText(asDouble(row['periodBalance']))),
                      DataCell(
                        MoneyText(
                          asDouble(row['balance']),
                          colorNegative: true,
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

class _SupplierPayablesTab extends StatefulWidget {
  const _SupplierPayablesTab();

  @override
  State<_SupplierPayablesTab> createState() => _SupplierPayablesTabState();
}

class _SupplierPayablesTabState extends State<_SupplierPayablesTab> {
  DateTime? _from;
  DateTime? _to;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    final s = context.s;
    final totals = controller.supplierPayablesTotals;
    return ReportAsyncSection(
      loading: controller.loadingSupplierPayables,
      error: controller.supplierPayablesError,
      isEmpty: controller.supplierPayables.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: () =>
          controller.loadSupplierPayables(from: _from, to: _to),
      header: ReportHeader(
        onPrint: () => PrintService.printSupplierPayables(
          context,
          from: _from,
          to: _to,
        ),
        filters: <Widget>[
          DateRangeButton(
            from: _from,
            to: _to,
            onChanged: (from, to) {
              setState(() {
                _from = from;
                _to = to;
              });
              controller.loadSupplierPayables(from: from, to: to);
            },
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.totals,
          child: Column(
            children: <Widget>[
              ReportKeyValueRow(
                label: s.purchases,
                amount: asDouble(totals['purchases']),
              ),
              ReportKeyValueRow(
                label: s.paid,
                amount: asDouble(totals['paid']),
              ),
              ReportKeyValueRow(
                label: s.balance,
                amount: asDouble(totals['balance']),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.supplierPayables,
          subtitle: s.supplierPayablesHint,
          child: Column(
            children: <Widget>[
              for (final row in controller.supplierPayables)
                _SupplierPayableTile(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupplierPayableTile extends StatelessWidget {
  const _SupplierPayableTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final phone = asStringOrNull(row['phone']);
    final orders = s.poCountLabel(
      Formatters.integer(asDouble(row['purchaseOrders'])),
    );
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(asString(row['supplier'], fallback: s.supplier)),
      subtitle: Text(phone == null ? orders : '$phone · $orders'),
      trailing: MoneyText(asDouble(row['balance']), colorNegative: true),
    );
  }
}

class _StockBalanceTab extends StatefulWidget {
  const _StockBalanceTab();

  @override
  State<_StockBalanceTab> createState() => _StockBalanceTabState();
}

class _StockBalanceTabState extends State<_StockBalanceTab> {
  String? _warehouseId;
  List<Warehouse> _warehouses = <Warehouse>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWarehouses());
  }

  Future<void> _loadWarehouses() async {
    try {
      final page = await context.read<Session>().api.getPage<Warehouse>(
            '/warehouses',
            query: <String, dynamic>{'page': 1, 'pageSize': 100},
            parse: Warehouse.fromJson,
          );
      if (!mounted) return;
      setState(() => _warehouses = page.items);
    } catch (_) {
      // Ignore: the filter simply stays empty.
    }
  }

  Future<void> _reload() => context
      .read<ReportsController>()
      .loadStockBalance(warehouseId: _warehouseId);

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    final s = context.s;
    final totals = controller.stockBalanceTotals;
    return ReportAsyncSection(
      loading: controller.loadingStockBalance,
      error: controller.stockBalanceError,
      isEmpty: controller.stockBalance.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: _reload,
      header: ReportHeader(
        onPrint: () => PrintService.printStockBalance(
          context,
          warehouseId: _warehouseId,
        ),
        filters: <Widget>[
          SizedBox(
            width: 220,
            child: AppSelectField<String>(
              label: s.warehouse,
              value: _warehouseId ?? '',
              hint: s.allWarehouses,
              options: <SelectOption<String>>[
                SelectOption<String>('', s.allWarehouses),
                ..._warehouses.map(
                  (warehouse) => SelectOption<String>(
                    warehouse.id,
                    warehouse.name,
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _warehouseId =
                    (value == null || value.isEmpty) ? null : value);
                _reload();
              },
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () => pushScreen<void>(
              context,
              s.itemMovement,
              const ItemMovementScreen(),
            ),
            icon: const Icon(Icons.timeline_outlined),
            label: Text(s.itemMovement),
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.totals,
          child: Column(
            children: <Widget>[
              ReportKeyValueRow(
                label: s.stockLines,
                value: Formatters.integer(controller.stockBalance.length),
              ),
              ReportKeyValueRow(
                label: s.quantity,
                value: Formatters.integer(asDouble(totals['quantity'])),
              ),
              ReportKeyValueRow(
                label: s.costValue,
                amount: asDouble(totals['costValue']),
              ),
              ReportKeyValueRow(
                label: s.retailValue,
                amount: asDouble(totals['retailValue']),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.stockBalance,
          subtitle: s.stockBalanceHint,
          child: Column(
            children: <Widget>[
              for (final row in controller.stockBalance)
                _StockBalanceTile(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _StockBalanceTile extends StatelessWidget {
  const _StockBalanceTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final sku = asString(row['sku']);
    final warehouse = asString(row['warehouse']);
    final quantity = Formatters.integer(asDouble(row['quantity']));
    final available = Formatters.integer(asDouble(row['available']));
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        asString(row['name'], fallback: sku.isEmpty ? s.product : sku),
      ),
      subtitle: Text(
        '$sku · $warehouse · ${s.quantity}: $quantity · '
        '${s.available}: $available',
      ),
      trailing: MoneyText(asDouble(row['costValue'])),
    );
  }
}

class SalesSeriesRow extends StatelessWidget {
  const SalesSeriesRow({super.key, required this.point, this.showQuantity = false});

  final SalesPoint point;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(point.label, style: theme.textTheme.bodyMedium),
          ),
          if (showQuantity)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Text(
                '×${Formatters.integer(point.quantity)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          MoneyText(point.value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// (key/value rows live in report_widgets.dart)