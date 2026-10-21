import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/app_settings.dart';
import '../../models/dashboard_summary.dart';
import '../../state/reports_controller.dart';
import '../../state/settings_controller.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../products/products_screen.dart';

/// Landing screen with KPIs, recent inventory movements and low-stock alerts.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _lowStock = <Map<String, dynamic>>[];
  bool _loadingLowStock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<ReportsController>();
      if (controller.dashboard == null) {
        controller.loadDashboard();
      }
      final settings = context.read<SettingsController>();
      if (settings.settings == null && !settings.loading) {
        settings.load();
      }
      _loadLowStock();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLowStock() async {
    setState(() => _loadingLowStock = true);
    try {
      final rows = await context.read<DashboardController>().loadLowStock();
      if (!mounted) return;
      setState(() => _lowStock = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _lowStock = <Map<String, dynamic>>[]);
    } finally {
      if (mounted) setState(() => _loadingLowStock = false);
    }
  }

  Future<void> _refresh() async {
    final controller = context.read<ReportsController>();
    await Future.wait(<Future<void>>[
      controller.loadDashboard(),
      _loadLowStock(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final summary = controller.dashboard;
    final session = context.watch<Session>();
    final settings = context.watch<SettingsController>();
    final widgets =
        AppSettings.parseDashboardWidgets(settings.settings?.dashboardWidgets);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: Scrollbar(
        controller: _scrollController,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: <Widget>[
          if (controller.loadingDashboard && summary == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.dashboardError != null && summary == null)
            SectionCard(
              child: Column(
                children: <Widget>[
                  Text(
                    controller.dashboardError!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: controller.loadDashboard,
                    icon: const Icon(Icons.refresh),
                    label: Text(s.retry),
                  ),
                ],
              ),
            )
          else if (summary != null && widgets.contains('kpis')) ...<Widget>[
            _KpiGrid(summary: summary),
            const SizedBox(height: 16),
          ],
          if (widgets.contains('quickActions') &&
              session.can('products')) ...<Widget>[
            SectionCard(
              title: s.quickActions,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  if (session.can('products'))
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProductsScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(s.products),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widgets.contains('lowStock'))
            SectionCard(
              title: s.lowStockAlerts,
              subtitle: _lowStock.isEmpty
                  ? s.everythingAboveReorder
                  : s.productsNeedAttention(_lowStock.length),
              trailing: IconButton(
                tooltip: s.refresh,
                onPressed: _loadingLowStock ? null : _loadLowStock,
                icon: _loadingLowStock
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
              child: _lowStock.isEmpty
                  ? Text(
                      s.noLowStockItems,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    )
                  : Column(
                      children: _lowStock
                          .take(8)
                          .map((row) => _LowStockTile(row: row))
                          .toList(),
                    ),
            ),
          if (widgets.contains('lowStock') && widgets.contains('recentMovements'))
            const SizedBox(height: 16),
          if (widgets.contains('recentMovements'))
            SectionCard(
              title: s.recentMovements,
              child: (summary?.movements.isEmpty ?? true)
                  ? Text(
                      s.noRecentMovements,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    )
                  : SizedBox(
                      height: 280,
                      child: Scrollbar(
                        child: ListView.builder(
                          itemCount: summary!.movements.length,
                          itemBuilder: (context, index) {
                            final row = summary.movements[index];
                            return _MovementTile(row: row);
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact KPI card used by the dashboard grid.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final tiles = <Widget>[
      _KpiCard(
        label: s.salesToday,
        icon: Icons.today_outlined,
        child: MoneyText(summary.salesToday, currencyCode: summary.currencyCode),
      ),
      _KpiCard(
        label: s.salesThisMonth,
        icon: Icons.trending_up,
        child: MoneyText(
          summary.salesThisMonth,
          currencyCode: summary.currencyCode,
        ),
      ),
      _KpiCard(
        label: s.receivables,
        icon: Icons.request_quote_outlined,
        child: MoneyText(summary.receivables, currencyCode: summary.currencyCode),
      ),
      _KpiCard(
        label: s.inventoryValue,
        icon: Icons.warehouse_outlined,
        child: MoneyText(
          summary.inventoryValue,
          currencyCode: summary.currencyCode,
        ),
      ),
      _KpiCard(
        label: s.lowStockItems,
        icon: Icons.warning_amber_outlined,
        child: Text(Formatters.integer(summary.lowStockCount)),
      ),
      _KpiCard(
        label: s.products,
        icon: Icons.inventory_2_outlined,
        child: Text(Formatters.integer(summary.productCount)),
      ),
      _KpiCard(
        label: s.customers,
        icon: Icons.people_outline,
        child: Text(Formatters.integer(summary.customerCount)),
      ),
      _KpiCard(
        label: s.openInvoices,
        icon: Icons.description_outlined,
        child: Text(Formatters.integer(summary.invoiceCount)),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 700
                ? 2
                : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.icon,
    required this.child,
  });

  final String label;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _LowStockTile extends StatelessWidget {
  const _LowStockTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final name = (row['product'] is Map)
        ? (row['product'] as Map)['name']
        : (row['name'] ?? row['productName']);
    final quantity = row['quantity'] ?? row['onHand'] ?? 0;
    final reorder = row['reorderLevel'] ?? row['reorder'] ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.warning_amber_outlined),
      title: Text(name ?? context.s.productFallback),
      subtitle: Text(context.s.reorderLevelValue(
          Formatters.integer(reorder as num?))),
      trailing: Text(
        Formatters.integer(quantity as num?),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final product = row['product'];
    final name = (product is Map ? product['name'] : null) ??
        row['productName'] ??
        context.s.productFallback;
    final quantity = row['quantity'] ?? 0;
    final type = row['type']?.toString();
    final created = row['createdAt']?.toString();
    final date = created == null ? null : DateTime.tryParse(created);
    final s = context.s;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        (quantity is num && quantity < 0)
            ? Icons.south_west
            : Icons.north_east,
      ),
      title: Text('$name'),
      subtitle: Text(
        '${s.status(type)} · ${Formatters.dateTime(date)}',
      ),
      trailing: Text(
        Formatters.integer(quantity as num?),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
