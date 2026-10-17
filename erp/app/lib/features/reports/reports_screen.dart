import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../models/sales_point.dart';
import '../../models/warehouse.dart';
import '../../state/reports_controller.dart';
import '../../state/salespeople_controller.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../customers/customer_statement_screen.dart';
import '../shell/navigation.dart';
import '../suppliers/supplier_statement_screen.dart';
import 'item_movement_screen.dart';
import 'statement_hub_screen.dart';

/// Read-only reports: sales, top products, inventory valuation and customer
/// balances.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<ReportsController>();
      controller.loadSales(groupBy: 'day');
      controller.loadTopProducts();
      controller.loadValuation();
      controller.loadCustomerBalances();
      controller.loadSupplierBalances();
      controller.loadReceivables();
      controller.loadSupplierPayables();
      controller.loadStockBalance();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return DefaultTabController(
      length: 9,
      child: Column(
        children: <Widget>[
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(text: s.sales),
              Tab(text: s.topProducts),
              Tab(text: s.valuation),
              Tab(text: s.customerBalances),
              Tab(text: s.supplierBalances),
              Tab(text: s.receivablesBySalesperson),
              Tab(text: s.supplierPayables),
              Tab(text: s.stockBalance),
              Tab(text: s.statements),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                const _SalesTab(),
                const _TopProductsTab(),
                const _ValuationTab(),
                const _CustomerBalancesTab(),
                const _SupplierBalancesTab(),
                const _ReceivablesTab(),
                const _SupplierPayablesTab(),
                const _StockBalanceTab(),
                const _StatementsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesTab extends StatelessWidget {
  const _SalesTab();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    final s = context.s;
    return _AsyncSection(
      loading: controller.loadingSales,
      error: controller.salesError,
      isEmpty: controller.salesSeries.isEmpty,
      emptyTitle: s.noSalesInPeriod,
      onRetry: () => controller.loadSales(groupBy: 'day'),
      header: _PrintBar(
        onPrint: () => PrintService.printSalesReport(context, groupBy: 'day'),
      ),
      children: <Widget>[
        SectionCard(
          title: s.salesByDay,
          subtitle: s.revenuePerDay,
          child: Column(
            children: <Widget>[
              for (final point in controller.salesSeries)
                _SeriesRow(point: point),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopProductsTab extends StatelessWidget {
  const _TopProductsTab();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    final s = context.s;
    return _AsyncSection(
      loading: controller.loadingTopProducts,
      error: controller.topProductsError,
      isEmpty: controller.topProducts.isEmpty,
      emptyTitle: s.noProductSalesYet,
      onRetry: controller.loadTopProducts,
      header: _PrintBar(
        onPrint: () => PrintService.printTopProducts(context, limit: 10),
      ),
      children: <Widget>[
        SectionCard(
          title: s.topProducts,
          subtitle: s.last30Days,
          child: Column(
            children: <Widget>[
              for (final point in controller.topProducts)
                _SeriesRow(point: point, showQuantity: true),
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
    return _AsyncSection(
      loading: controller.loadingValuation,
      error: controller.valuationError,
      isEmpty: rows.isEmpty && valuation.isEmpty,
      emptyTitle: s.noStockToValuate,
      onRetry: controller.loadValuation,
      header: _PrintBar(
        onPrint: () => PrintService.printInventoryValuation(context),
      ),
      children: <Widget>[
        if (totals is Map)
          SectionCard(
            title: s.totals,
            child: Column(
              children: <Widget>[
                _KeyValueRow(
                  label: s.stockLines,
                  value: Formatters.integer(_num(totals['lines'])),
                ),
                _KeyValueRow(
                  label: s.units,
                  value: Formatters.integer(_num(totals['units'])),
                ),
                _KeyValueRow(
                  label: s.costValue,
                  amount: _num(totals['costValue']),
                ),
                _KeyValueRow(
                  label: s.retailValue,
                  amount: _num(totals['retailValue']),
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
                    s.lineWithQty(
                      '${row['sku'] ?? ''}',
                      Formatters.integer(_num(row['quantity'])),
                    ),
                  ),
                  trailing: MoneyText(_num(row['costValue'])),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerBalancesTab extends StatelessWidget {
  const _CustomerBalancesTab();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    final s = context.s;
    return _AsyncSection(
      loading: controller.loadingCustomerBalances,
      error: controller.customerBalancesError,
      isEmpty: controller.customerBalances.isEmpty,
      emptyTitle: s.noOutstandingBalances,
      onRetry: controller.loadCustomerBalances,
      children: <Widget>[
        SectionCard(
          title: s.customerBalances,
          subtitle: s.customerCountLabel('${controller.customerBalances.length}'),
          child: Column(
            children: <Widget>[
              for (final row in controller.customerBalances)
                _CustomerBalanceTile(row: row),
            ],
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
    return _AsyncSection(
      loading: controller.loadingSupplierBalances,
      error: controller.supplierBalancesError,
      isEmpty: controller.supplierBalances.isEmpty,
      emptyTitle: s.noOutstandingBalances,
      onRetry: controller.loadSupplierBalances,
      children: <Widget>[
        SectionCard(
          title: s.supplierBalances,
          subtitle: s.supplierCountLabel('${controller.supplierBalances.length}'),
          child: Column(
            children: <Widget>[
              for (final row in controller.supplierBalances)
                _SupplierBalanceTile(row: row),
            ],
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
    return _AsyncSection(
      loading: controller.loadingReceivables,
      error: controller.receivablesError,
      isEmpty: controller.receivables.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: _reload,
      header: _ReportHeader(
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
              _KeyValueRow(
                label: s.total,
                amount: _num(totals['total']),
              ),
              _KeyValueRow(
                label: s.paid,
                amount: _num(totals['paid']),
              ),
              _KeyValueRow(
                label: s.balance,
                amount: _num(totals['balance']),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.receivablesBySalesperson,
          subtitle: s.receivablesBySalespersonHint,
          child: Column(
            children: <Widget>[
              for (final row in controller.receivables)
                _ReceivableTile(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceivableTile extends StatelessWidget {
  const _ReceivableTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final salesperson = asStringOrNull(row['salesperson']) ?? s.unassigned;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(asString(row['customer'], fallback: s.customer)),
      subtitle: Text(
        '$salesperson · '
        '${s.invoiceCountLabel(Formatters.integer(_num(row['invoices'])))}',
      ),
      trailing: MoneyText(_num(row['balance']), colorNegative: true),
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
    return _AsyncSection(
      loading: controller.loadingSupplierPayables,
      error: controller.supplierPayablesError,
      isEmpty: controller.supplierPayables.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: () =>
          controller.loadSupplierPayables(from: _from, to: _to),
      header: _ReportHeader(
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
              _KeyValueRow(
                label: s.purchases,
                amount: _num(totals['purchases']),
              ),
              _KeyValueRow(
                label: s.paid,
                amount: _num(totals['paid']),
              ),
              _KeyValueRow(
                label: s.balance,
                amount: _num(totals['balance']),
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
      Formatters.integer(_num(row['purchaseOrders'])),
    );
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(asString(row['supplier'], fallback: s.supplier)),
      subtitle: Text(phone == null ? orders : '$phone · $orders'),
      trailing: MoneyText(_num(row['balance']), colorNegative: true),
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
    return _AsyncSection(
      loading: controller.loadingStockBalance,
      error: controller.stockBalanceError,
      isEmpty: controller.stockBalance.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: _reload,
      header: _ReportHeader(
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
              _KeyValueRow(
                label: s.stockLines,
                value: Formatters.integer(controller.stockBalance.length),
              ),
              _KeyValueRow(
                label: s.quantity,
                value: Formatters.integer(_num(totals['quantity'])),
              ),
              _KeyValueRow(
                label: s.costValue,
                amount: _num(totals['costValue']),
              ),
              _KeyValueRow(
                label: s.retailValue,
                amount: _num(totals['retailValue']),
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
    final quantity = Formatters.integer(_num(row['quantity']));
    final available = Formatters.integer(_num(row['available']));
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
      trailing: MoneyText(_num(row['costValue'])),
    );
  }
}

class _StatementsTab extends StatelessWidget {
  const _StatementsTab();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        SectionCard(
          title: s.statements,
          subtitle: s.statementsHint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: () => pushScreen<void>(
                  context,
                  s.statements,
                  const StatementHubScreen(
                    startWith: StatementKind.customer,
                  ),
                ),
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(s.customerStatement),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => pushScreen<void>(
                  context,
                  s.statements,
                  const StatementHubScreen(startWith: StatementKind.supplier),
                ),
                icon: const Icon(Icons.local_shipping_outlined),
                label: Text(s.supplierStatement),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A print bar plus an optional row of filter controls.
class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.onPrint, this.filters = const <Widget>[]});

  final VoidCallback onPrint;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PrintBar(onPrint: onPrint),
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

class _AsyncSection extends StatelessWidget {
  const _AsyncSection({
    required this.loading,
    required this.error,
    required this.isEmpty,
    required this.emptyTitle,
    required this.onRetry,
    required this.children,
    this.header,
  });

  final bool loading;
  final String? error;
  final bool isEmpty;
  final String emptyTitle;
  final Future<void> Function() onRetry;
  final List<Widget> children;
  final Widget? header;

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
            EmptyState(icon: Icons.insights_outlined, title: emptyTitle),
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

class _PrintBar extends StatelessWidget {
  const _PrintBar({required this.onPrint});

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

class _CustomerBalanceTile extends StatelessWidget {
  const _CustomerBalanceTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final name = asString(row['name'], fallback: s.customer);
    final id = asStringOrNull(row['id']) ?? asStringOrNull(row['customerId']);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(name),
      subtitle: Text(s.invoiceCountLabel('${row['invoices'] ?? 0}')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MoneyText(_num(row['balance']), colorNegative: true),
          if (id != null) ...<Widget>[
            const SizedBox(width: 4),
            IconButton(
              tooltip: s.accountStatement,
              icon: const Icon(Icons.list_alt_outlined),
              onPressed: () => openCustomerStatement(
                context,
                customerId: id,
                customerName: name,
              ),
            ),
          ],
        ],
      ),
      onTap: id == null
          ? null
          : () => openCustomerStatement(
                context,
                customerId: id,
                customerName: name,
              ),
    );
  }
}

class _SupplierBalanceTile extends StatelessWidget {
  const _SupplierBalanceTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final name = asString(row['name'], fallback: s.supplier);
    final id = asStringOrNull(row['id']) ?? asStringOrNull(row['supplierId']);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(name),
      subtitle: Text(
        s.poCountLabel('${row['purchaseOrders'] ?? row['invoices'] ?? 0}'),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MoneyText(_num(row['balance']), colorNegative: true),
          if (id != null) ...<Widget>[
            const SizedBox(width: 4),
            IconButton(
              tooltip: s.accountStatement,
              icon: const Icon(Icons.list_alt_outlined),
              onPressed: () => openSupplierStatement(
                context,
                supplierId: id,
                supplierName: name,
              ),
            ),
          ],
        ],
      ),
      onTap: id == null
          ? null
          : () => openSupplierStatement(
                context,
                supplierId: id,
                supplierName: name,
              ),
    );
  }
}

class _SeriesRow extends StatelessWidget {
  const _SeriesRow({required this.point, this.showQuantity = false});

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

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, this.value, this.amount});

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

double _num(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
