import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
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

  void _reloadIfProduct() {
    if (_product != null) _apply();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      body: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppTheme.isLight(context)
                  ? const Color(0xFFEDF1F5)
                  : Theme.of(context).colorScheme.surfaceContainerHigh,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 620;
                final dateButton = DateRangeButton(
                  from: _from,
                  to: _to,
                  onChanged: (from, to) {
                    setState(() {
                      _from = from;
                      _to = to;
                    });
                    _reloadIfProduct();
                  },
                );
                final warehouseField = AppSelectField<String>(
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
                    setState(
                      () => _warehouseId =
                          (value == null || value.isEmpty) ? null : value,
                    );
                    _reloadIfProduct();
                  },
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ProductPickerField(
                      product: _product,
                      label: s.chooseProduct,
                      onChanged: (product) {
                        setState(() => _product = product);
                        _reloadIfProduct();
                      },
                    ),
                    const SizedBox(height: 8),
                    if (wide)
                      Row(
                        children: <Widget>[
                          Expanded(child: dateButton),
                          const SizedBox(width: 8),
                          SizedBox(width: 240, child: warehouseField),
                        ],
                      )
                    else ...<Widget>[
                      dateButton,
                      const SizedBox(height: 8),
                      warehouseField,
                    ],
                  ],
                );
              },
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

    final unit = asString(product['unit']);
    final openingQty = _num(opening['quantity']);
    final openingValue = _num(opening['value']);
    final inQty = _num(totals['inQty']);
    final outQty = _num(totals['outQty']);
    final closingQty = _num(totals['closingQty']);
    final closingValue = _num(totals['closingValue']);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async => _apply(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          SectionCard(
            title: asString(product['name'], fallback: s.product),
            subtitle: '${asString(product['sku'])} · $unit',
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720 ? 4 : 2;
                const gap = 8.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    SizedBox(
                      width: width,
                      child: _SummaryTile(
                        label: s.openingShort,
                        quantity: openingQty,
                        value: openingValue,
                        unit: unit,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _SummaryTile(
                        label: s.inShort,
                        quantity: inQty,
                        value: _num(totals['inValue']),
                        unit: unit,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _SummaryTile(
                        label: s.outShort,
                        quantity: outQty,
                        value: _num(totals['outValue']),
                        unit: unit,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _SummaryTile(
                        label: s.closingShort,
                        quantity: closingQty,
                        value: closingValue,
                        unit: unit,
                        emphasise: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: s.itemMovement,
            subtitle: s.itemMovementHint,
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columnSpacing: 18,
                horizontalMargin: 12,
                headingRowHeight: 38,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 60,
                columns: <DataColumn>[
                  DataColumn(label: Text(s.date)),
                  DataColumn(label: Text(s.numberLabel)),
                  DataColumn(label: Text(s.description)),
                  DataColumn(label: Text(s.inShort), numeric: true),
                  DataColumn(label: Text(s.outShort), numeric: true),
                  DataColumn(label: Text(s.balance), numeric: true),
                  DataColumn(label: Text(s.costValue), numeric: true),
                ],
                rows: <DataRow>[
                  DataRow(
                    color: WidgetStatePropertyAll<Color>(
                      theme.colorScheme.primary.withAlpha(14),
                    ),
                    cells: <DataCell>[
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      DataCell(
                        Text(
                          s.openingBalance,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      DataCell(
                        Text(
                          Formatters.integer(openingQty),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(MoneyText(openingValue)),
                    ],
                  ),
                  for (var index = 0; index < rows.length; index++)
                    _movementRow(context, rows[index], index),
                  DataRow(
                    color: WidgetStatePropertyAll<Color>(
                      AppTheme.sectionHeaderColor(context),
                    ),
                    cells: <DataCell>[
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      DataCell(
                        Text(
                          s.totals,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(inQty),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(outQty),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(closingQty),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        MoneyText(
                          closingValue,
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
      ),
    );
  }

  DataRow _movementRow(
    BuildContext context,
    Map<String, dynamic> row,
    int index,
  ) {
    final s = context.s;
    final theme = Theme.of(context);
    final isIn = asString(row['dir']).toUpperCase() == 'IN';
    final quantity = _num(row['quantity']).abs();
    final type = asString(row['type']);
    final party = asMap(row['party']);
    final partyType = asString(party['type']);
    final partyName = asStringOrNull(party['name']);
    final note = asStringOrNull(row['note']);
    final location = asStringOrNull(row['location']);

    String? partyLabel;
    if (partyType == 'CUSTOMER') {
      partyLabel =
          '${isIn ? s.fromCustomer : s.toCustomer}: ${partyName ?? '—'}';
    } else if (partyType == 'SUPPLIER') {
      partyLabel =
          '${isIn ? s.fromSupplier : s.toSupplier}: ${partyName ?? '—'}';
    } else if (partyType == 'CASH') {
      partyLabel = s.cashSale;
    }

    final details = <String>[
      if (partyLabel != null) partyLabel,
      if (location != null && location.isNotEmpty) location,
      if (note != null &&
          note.isNotEmpty &&
          !note.startsWith('Reversed fulfilment') &&
          !note.startsWith('Customer return') &&
          !note.startsWith('Received against') &&
          !note.startsWith('Void invoice'))
        note,
    ].join(' · ');

    final rowColor = index.isOdd
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(90)
        : null;

    return DataRow(
      color: rowColor == null ? null : WidgetStatePropertyAll<Color>(rowColor),
      cells: <DataCell>[
        DataCell(Text(Formatters.date(asDate(row['date'])))),
        DataCell(
          SizedBox(
            width: 130,
            child: Text(
              asString(row['reference'], fallback: '—'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.status(type),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        DataCell(
          isIn
              ? Text(
                  Formatters.integer(quantity),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                )
              : const Text(''),
        ),
        DataCell(
          isIn
              ? const Text('')
              : Text(
                  Formatters.integer(quantity),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.error,
                  ),
                ),
        ),
        DataCell(
          Text(
            Formatters.integer(_num(row['balance'])),
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        DataCell(MoneyText(_num(row['value']))),
      ],
    );
  }
}

/// A small KPI tile for the opening / in / out / closing figures.
class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.quantity,
    required this.value,
    required this.unit,
    this.color,
    this.emphasise = false,
  });

  final String label;
  final double quantity;
  final double value;
  final String unit;
  final Color? color;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantityColor = color ?? theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: emphasise
            ? AppTheme.sectionHeaderColor(context)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                Formatters.integer(quantity),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: quantityColor,
                ),
              ),
              const SizedBox(width: 4),
              Text(unit, style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 1),
          MoneyText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
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
