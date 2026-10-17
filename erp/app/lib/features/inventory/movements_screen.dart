import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/stock_movement.dart';
import '../../models/warehouse.dart';
import '../../state/inventory_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

const List<String> _movementTypes = <String>[
  'OPENING',
  'RECEIVE',
  'DISPATCH',
  'ADJUSTMENT',
  'TRANSFER_IN',
  'TRANSFER_OUT',
  'SALE',
  'SALE_RETURN',
  'PURCHASE',
  'PURCHASE_RETURN',
  'CYCLE_COUNT',
];

/// Inventory movement history with type / warehouse filters and search.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
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

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<MovementsController>();

    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: <Widget>[
                AppSearchField(
                  hintText: s.searchMovementsHint,
                  initialValue: controller.search,
                  onChanged: controller.searchWith,
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppSelectField<String>(
                        label: s.type,
                        value: controller.type,
                        hint: s.allTypes,
                        options: <SelectOption<String>>[
                          SelectOption<String>('', s.allTypes),
                          ..._movementTypes.map(
                            (type) => SelectOption<String>(
                              type,
                              s.status(type),
                            ),
                          ),
                        ],
                        onChanged: (value) => controller.filterByType(
                          value == null || value.isEmpty ? null : value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                              warehouse.name,
                            ),
                          ),
                        ],
                        onChanged: (value) => controller.filterByWarehouse(
                          value == null || value.isEmpty ? null : value,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncListView<StockMovement>(
              controller: controller,
              emptyIcon: Icons.swap_vert,
              emptyTitle: s.noMovements,
              emptyMessage: s.movementsWillAppear,
              itemBuilder: (context, movement, index) => _MovementTile(
                movement: movement,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final StockMovement movement;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final positive = movement.quantity >= 0;
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: positive
              ? const Color(0x1F2E7D32)
              : theme.colorScheme.errorContainer,
          child: Icon(
            positive ? Icons.north_east : Icons.south_west,
            size: 18,
            color: positive
                ? const Color(0xFF2E7D32)
                : theme.colorScheme.onErrorContainer,
          ),
        ),
        title: Text(movement.productName ?? s.product),
        subtitle: Text(
          '${s.status(movement.type)} · '
          '${movement.locationCode ?? '—'} · '
          '${Formatters.dateTime(movement.createdAt)}'
          '${movement.reference == null ? '' : ' · ${movement.reference}'}',
        ),
        trailing: Text(
          '${positive ? '+' : ''}${Formatters.integer(movement.quantity)}',
          style: theme.textTheme.titleMedium?.copyWith(
            color: positive ? const Color(0xFF2E7D32) : theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}
