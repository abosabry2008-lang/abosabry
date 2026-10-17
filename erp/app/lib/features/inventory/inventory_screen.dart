import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/stock_level.dart';
import '../../models/warehouse.dart';
import '../../state/inventory_controller.dart';
import '../../state/product_catalog.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import 'adjust_dialog.dart';
import 'cycle_count_dialog.dart';
import 'receive_dialog.dart';
import 'transfer_dialog.dart';

/// Stock levels with warehouse filter, low-stock filter and quick actions for
/// adjusting, transferring, receiving and cycle counting.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
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
      // The filter simply stays empty; the list still loads.
    }
  }

  Future<void> _afterMutation() async {
    final stock = context.read<StockController>();
    final catalog = context.read<ProductCatalog>();
    await stock.refresh();
    await catalog.load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<StockController>();
    final canManage = context.watch<Session>().can('inventory');

    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: <Widget>[
                AppSearchField(
                  hintText: s.searchStockHint,
                  initialValue: controller.search,
                  onChanged: controller.searchWith,
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppSelectField<String>(
                        label: s.warehouse,
                        value: controller.warehouseId,
                        hint: s.allWarehouses,
                        options: <SelectOption<String>>[
                          SelectOption<String>('', s.allWarehouses),
                          ..._warehouses.map(
                            (warehouse) => SelectOption<String>(
                              warehouse.id,
                              '${warehouse.code} — ${warehouse.name}',
                            ),
                          ),
                        ],
                        onChanged: (value) => controller.filterByWarehouse(
                          value == null || value.isEmpty ? null : value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(s.lowStock),
                      selected: controller.lowStockOnly,
                      onSelected: controller.setLowStockOnly,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncListView<StockLevel>(
              controller: controller,
              emptyIcon: Icons.warehouse_outlined,
              emptyTitle: s.noStockRecords,
              emptyMessage: s.receiveOrAdjustHint,
              itemBuilder: (context, level, index) => _StockTile(
                level: level,
                canManage: canManage,
                onAction: (action) => _runAction(action, level),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _showActions,
              icon: const Icon(Icons.add),
              label: Text(s.stock),
            )
          : null,
    );
  }

  Future<void> _showActions() async {
    final s = context.s;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.exposure),
              title: Text(s.adjustStock),
              onTap: () => Navigator.of(sheetContext).pop('adjust'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(s.transferStock),
              onTap: () => Navigator.of(sheetContext).pop('transfer'),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(s.receiveStock),
              onTap: () => Navigator.of(sheetContext).pop('receive'),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text(s.cycleCount),
              onTap: () => Navigator.of(sheetContext).pop('count'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    await _runAction(action, null);
  }

  Future<void> _runAction(String action, StockLevel? level) async {
    final catalog = context.read<ProductCatalog>();
    if (level != null) {
      await catalog.ensureLoaded();
      if (!mounted) return;
    }
    final product = level == null ? null : catalog.byId(level.productId);
    final location = level == null
        ? null
        : Location(
            id: level.locationId,
            warehouseId: level.warehouseId,
            code: level.locationCode ?? '',
          );

    bool success = false;
    switch (action) {
      case 'adjust':
        success = await showAdjustDialog(
          context,
          product: product,
          location: location,
          warehouseId: level?.warehouseId,
        );
        break;
      case 'transfer':
        success = await showTransferDialog(
          context,
          product: product,
          fromLocation: location,
          warehouseId: level?.warehouseId,
        );
        break;
      case 'receive':
        success = await showReceiveDialog(
          context,
          product: product,
          location: location,
          warehouseId: level?.warehouseId,
        );
        break;
      case 'count':
        success = await showCycleCountDialog(
          context,
          location: location,
          warehouseId: level?.warehouseId,
        );
        break;
    }

    if (!mounted || !success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.s.inventoryUpdated)),
    );
    await _afterMutation();
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({
    required this.level,
    required this.canManage,
    required this.onAction,
  });

  final StockLevel level;
  final bool canManage;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: level.isLowStock
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.inventory_2_outlined,
            size: 18,
            color: level.isLowStock
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(level.productName ?? s.product),
        subtitle: Text(
          '${level.sku ?? '—'} · ${level.warehouseName ?? s.warehouse} / '
          '${level.locationCode ?? '—'}'
          '${level.reserved > 0 ? ' · ${level.reserved} ${s.reserved}' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  Formatters.integer(level.quantity),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: level.isLowStock ? theme.colorScheme.error : null,
                  ),
                ),
                if (level.isLowStock)
                  Text(
                    s.low,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
              ],
            ),
            if (canManage)
              PopupMenuButton<String>(
                onSelected: onAction,
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'adjust',
                    child: Text(s.adjust),
                  ),
                  PopupMenuItem<String>(
                    value: 'transfer',
                    child: Text(s.transfer),
                  ),
                  PopupMenuItem<String>(
                    value: 'receive',
                    child: Text(s.receive),
                  ),
                  PopupMenuItem<String>(
                    value: 'count',
                    child: Text(s.cycleCount),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
