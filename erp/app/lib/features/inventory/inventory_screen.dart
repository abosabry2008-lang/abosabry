import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/stock_level.dart';
import '../../models/warehouse.dart';
import '../../state/categories_controller.dart';
import '../../state/inventory_controller.dart';
import '../../state/product_catalog.dart';
import '../../state/products_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import '../products/product_import_screen.dart';
import '../shell/navigation.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CategoriesController>().ensureLoaded();
    });
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
                      child: OutlinedButton.icon(
                        onPressed: _openFilters,
                        icon: Badge(
                          isLabelVisible: controller.hasActiveFilters,
                          label: Text(
                            controller.hasActiveFilters ? '!' : '',
                          ),
                          child: const Icon(Icons.tune, size: 20),
                        ),
                        label: Text(s.filters),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _sortButton(s, controller)),
                  ],
                ),
                if (controller.hasActiveFilters) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: <Widget>[
                      if (controller.warehouseId != null)
                        _filterChip(
                          _warehouseName(controller.warehouseId!),
                          () => controller.filterByWarehouse(null),
                        ),
                      if (controller.categoryId != null)
                        _filterChip(
                          _categoryName(controller.categoryId!),
                          () => controller.filterByCategory(null),
                        ),
                      if (controller.status.isNotEmpty)
                        _filterChip(
                          _statusLabel(s, controller.status),
                          () => controller.setStatus(''),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.clear_all, size: 16),
                        label: Text(s.clearFilters),
                        onPressed: controller.resetFilters,
                      ),
                    ],
                  ),
                ],
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

  Future<void> _openFilters() async {
    final s = context.s;
    final controller = context.read<StockController>();
    final categories = context.read<CategoriesController>().items;
    var warehouseId = controller.warehouseId ?? '';
    var categoryId = controller.categoryId ?? '';
    var status = controller.status;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.tune),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.filters,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setSheetState(() {
                        warehouseId = '';
                        categoryId = '';
                        status = '';
                      }),
                      child: Text(s.clearFilters),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppSelectField<String>(
                  label: s.warehouse,
                  value: warehouseId,
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
                  onChanged: (value) =>
                      setSheetState(() => warehouseId = value ?? ''),
                ),
                const SizedBox(height: 12),
                AppSelectField<String>(
                  label: s.category,
                  value: categoryId,
                  hint: s.allCategories,
                  options: <SelectOption<String>>[
                    SelectOption<String>('', s.allCategories),
                    ...categories.map(
                      (category) => SelectOption<String>(
                        category.id,
                        category.name,
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => categoryId = value ?? ''),
                ),
                const SizedBox(height: 16),
                Text(s.stockStatus, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      label: Text(s.allStatuses),
                      selected: status.isEmpty,
                      onSelected: (_) => setSheetState(() => status = ''),
                    ),
                    ChoiceChip(
                      label: Text(s.inStock),
                      selected: status == 'in',
                      onSelected: (_) => setSheetState(() => status = 'in'),
                    ),
                    ChoiceChip(
                      label: Text(s.lowStock),
                      selected: status == 'low',
                      onSelected: (_) => setSheetState(() => status = 'low'),
                    ),
                    ChoiceChip(
                      label: Text(s.outOfStock),
                      selected: status == 'out',
                      onSelected: (_) => setSheetState(() => status = 'out'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    controller.setFilters(
                      warehouseId: warehouseId,
                      categoryId: categoryId,
                      status: status,
                    );
                    Navigator.of(sheetContext).pop();
                  },
                  icon: const Icon(Icons.check),
                  label: Text(s.applyFilters),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sortButton(AppStrings s, StockController controller) {
    return PopupMenuButton<String>(
      tooltip: s.sortBy,
      onSelected: controller.setSort,
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'name', child: Text(s.sortName)),
        PopupMenuItem<String>(value: 'name_desc', child: Text(s.sortNameDesc)),
        PopupMenuItem<String>(value: 'sku', child: Text(s.sortSku)),
        PopupMenuItem<String>(
          value: 'quantity',
          child: Text(s.sortQuantityDesc),
        ),
        PopupMenuItem<String>(
          value: 'quantity_asc',
          child: Text(s.sortQuantityAsc),
        ),
        PopupMenuItem<String>(value: 'newest', child: Text(s.sortNewest)),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.sort, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _sortLabel(s, controller.sort),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, VoidCallback onDeleted) {
    return InputChip(
      label: Text(label),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close, size: 16),
    );
  }

  String _sortLabel(AppStrings s, String sort) {
    switch (sort) {
      case 'name_desc':
        return s.sortNameDesc;
      case 'sku':
        return s.sortSku;
      case 'quantity':
        return s.sortQuantityDesc;
      case 'quantity_asc':
        return s.sortQuantityAsc;
      case 'newest':
        return s.sortNewest;
      default:
        return s.sortName;
    }
  }

  String _statusLabel(AppStrings s, String status) {
    switch (status) {
      case 'in':
        return s.inStock;
      case 'low':
        return s.lowStock;
      case 'out':
        return s.outOfStock;
      default:
        return s.allStatuses;
    }
  }

  String _warehouseName(String id) {
    for (final warehouse in _warehouses) {
      if (warehouse.id == id) return warehouse.name;
    }
    return context.s.warehouse;
  }

  String _categoryName(String id) {
    for (final category in context.read<CategoriesController>().items) {
      if (category.id == id) return category.name;
    }
    return context.s.category;
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
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: Text(s.importProducts),
              onTap: () => Navigator.of(sheetContext).pop('import'),
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
    final s = context.s;
    if (action == 'import') {
      if (!mounted) return;
      final imported = await pushScreen<bool>(
        context,
        context.s.importProducts,
        const ProductImportScreen(),
      );
      if (imported == true) await _afterMutation();
      return;
    }
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
      case 'deleteProduct':
        if (product == null) return;
        if (!mounted) return;
        final confirmed = await confirmDialog(
          context,
          title: s.deleteProductQ,
          message: s.productWillBeRemoved(product.name),
          confirmLabel: s.delete,
          destructive: true,
        );
        if (!confirmed || !mounted) return;
        try {
          await context.read<ProductsController>().delete(product.id);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.productDeleted(product.name))),
          );
          await _afterMutation();
        } on ApiException catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
        return;
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
            if (canManage)
              IconButton(
                tooltip: s.deleteProduct,
                onPressed: () => onAction('deleteProduct'),
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
