import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../models/product.dart';
import '../../models/warehouse.dart';
import '../../state/reports_controller.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../inventory/product_picker_field.dart';

/// A single product's movement history with a running balance.
class ItemMovementScreen extends StatefulWidget {
  const ItemMovementScreen({super.key});

  @override
  State<ItemMovementScreen> createState() => _ItemMovementScreenState();
}

class _ItemMovementScreenState extends State<ItemMovementScreen> {
  Product? _product;
  DateTime? _from;
  DateTime? _to;
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

  void _apply() {
    final product = _product;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.selectProductFirst)),
      );
      return;
    }
    context.read<ReportsController>().loadItemMovement(
          productId: product.id,
          from: _from,
          to: _to,
          warehouseId: _warehouseId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: <Widget>[
                ProductPickerField(
                  product: _product,
                  label: s.chooseProduct,
                  onChanged: (product) => setState(() => _product = product),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DateRangeButton(
                        from: _from,
                        to: _to,
                        onChanged: (from, to) => setState(() {
                          _from = from;
                          _to = to;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
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
                        onChanged: (value) => setState(
                          () => _warehouseId =
                              (value == null || value.isEmpty) ? null : value,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.tonalIcon(
                    onPressed: _apply,
                    icon: const Icon(Icons.filter_alt_outlined),
                    label: Text(s.applyFilters),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final data = controller.itemMovement;
    final product = asMap(data['product']);
    final opening = asMap(data['opening']);
    final totals = asMap(data['totals']);
    final rows = asMapList(data['rows']);

    if (controller.loadingItemMovement && data.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.itemMovementError != null && data.isEmpty) {
      return ErrorView(
        message: controller.itemMovementError!,
        onRetry: _apply,
      );
    }
    if (data.isEmpty) {
      return EmptyState(
        icon: Icons.timeline_outlined,
        title: s.itemMovement,
        message: _product == null ? s.selectProductFirst : s.noDataForFilters,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _apply(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          SectionCard(
            title: asString(product['name'], fallback: s.product),
            subtitle: '${asString(product['sku'])} · ${asString(product['unit'])}',
            trailing: IconButton(
              tooltip: s.print,
              icon: const Icon(Icons.print_outlined),
              onPressed: () => PrintService.printItemMovement(
                context,
                productId: _product?.id ?? asString(product['id']),
                from: _from,
                to: _to,
                warehouseId: _warehouseId,
              ),
            ),
            child: Column(
              children: <Widget>[
                _KeyValueRow(
                  label: s.openingShort,
                  value: '${Formatters.integer(_num(opening['quantity']))} · '
                      '${Formatters.money(_num(opening['value']))}',
                ),
                _KeyValueRow(
                  label: s.inShort,
                  value: '${Formatters.integer(_num(totals['inQty']))} · '
                      '${Formatters.money(_num(totals['inValue']))}',
                ),
                _KeyValueRow(
                  label: s.outShort,
                  value: '${Formatters.integer(_num(totals['outQty']))} · '
                      '${Formatters.money(_num(totals['outValue']))}',
                ),
                _KeyValueRow(
                  label: s.closingShort,
                  value: '${Formatters.integer(_num(totals['closingQty']))} · '
                      '${Formatters.money(_num(totals['closingValue']))}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: s.itemMovement,
            subtitle: s.itemMovementHint,
            child: Column(
              children: <Widget>[
                for (final row in rows) _MovementRow(row: row),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final isIn = asString(row['dir']).toUpperCase() == 'IN';
    final quantity = _num(row['quantity']);
    final party = asMap(row['party']);
    final partyType = asString(party['type']);
    final partyName = asStringOrNull(party['name']);
    final partyLabel = party.isEmpty
        ? null
        : partyType == 'CASH'
            ? s.cashSale
            : partyType == 'CUSTOMER'
                ? '${isIn ? s.fromCustomer : s.toCustomer}: ${partyName ?? '—'}'
                : partyType == 'SUPPLIER'
                    ? '${isIn ? s.fromSupplier : s.toSupplier}: ${partyName ?? '—'}'
                    : null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${Formatters.date(asDate(row['date']))} · '
        '${s.status(asStringOrNull(row['type']))}',
      ),
      subtitle: Text(
        <String>[
          if (partyLabel != null) partyLabel,
          asString(row['reference'], fallback: '—'),
          asString(row['location'], fallback: '—'),
          '${s.runningBalance}: ${Formatters.integer(_num(row['balance']))}',
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            '${quantity >= 0 ? '+' : ''}${Formatters.integer(quantity)}',
            style: theme.textTheme.titleSmall?.copyWith(
              color:
                  isIn ? const Color(0xFF2E7D32) : theme.colorScheme.error,
            ),
          ),
          MoneyText(_num(row['value']), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// A compact key/value row used for the opening and totals summary.
class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(value, style: theme.textTheme.bodyMedium),
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
