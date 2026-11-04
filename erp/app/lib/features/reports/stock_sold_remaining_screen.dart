import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../state/categories_controller.dart';
import '../../state/warehouses_controller.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Stock report for a period: previous balance, receipts, sales and the
/// remaining balance per warehouse and product.
class StockSoldRemainingScreen extends StatefulWidget {
  const StockSoldRemainingScreen({super.key});

  @override
  State<StockSoldRemainingScreen> createState() =>
      _StockSoldRemainingScreenState();
}

class _StockSoldRemainingScreenState extends State<StockSoldRemainingScreen> {
  late DateTime _from;
  late DateTime _to;
  String? _warehouseId;
  String? _categoryId;
  String _search = '';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WarehousesController>().ensureLoaded();
      context.read<CategoriesController>().ensureLoaded();
      _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.getObject(
            '/reports/stock-sold-remaining',
            query: <String, dynamic>{
              'from': _from.toUtc().toIso8601String(),
              'to': Formatters.isoRangeEnd(_to),
              if (_warehouseId != null) 'warehouseId': _warehouseId,
              if (_categoryId != null) 'categoryId': _categoryId,
              if (_search.trim().isNotEmpty) 'search': _search.trim(),
            },
          );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.s.couldNotLoadReport;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final rows = asMapList(_data['rows']);
    final byWarehouse = asMapList(_data['byWarehouse']);
    final totals = asMap(_data['totals']);
    final warehouses = context.watch<WarehousesController>().items;
    final categories = context.watch<CategoriesController>().items;

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noStockMovement,
      emptyIcon: Icons.inventory_2_outlined,
      onRetry: _load,
      header: ReportHeader(
        filters: <Widget>[
          DateRangeButton(
            from: _from,
            to: _to,
            onChanged: (from, to) {
              setState(() {
                if (from != null) _from = from;
                if (to != null) _to = to;
              });
              _load();
            },
          ),
          AppSelectField<String>(
            label: s.warehouse,
            value: _warehouseId ?? '',
            hint: s.allWarehouses,
            prefixIcon: Icons.warehouse_outlined,
            options: <SelectOption<String>>[
              SelectOption<String>('', s.allWarehouses),
              ...warehouses.map(
                (warehouse) => SelectOption<String>(
                  warehouse.id,
                  '${warehouse.code} — ${warehouse.name}',
                ),
              ),
            ],
            onChanged: (value) {
              setState(
                () => _warehouseId =
                    (value == null || value.isEmpty) ? null : value,
              );
              _load();
            },
          ),
          AppSelectField<String>(
            label: s.category,
            value: _categoryId ?? '',
            hint: s.allCategories,
            prefixIcon: Icons.category_outlined,
            options: <SelectOption<String>>[
              SelectOption<String>('', s.allCategories),
              ...categories.map(
                (category) => SelectOption<String>(
                  category.id,
                  category.name,
                ),
              ),
            ],
            onChanged: (value) {
              setState(
                () => _categoryId =
                    (value == null || value.isEmpty) ? null : value,
              );
              _load();
            },
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: AppSearchField(
                  hintText: s.searchStockHint,
                  initialValue: _search,
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.search),
                label: Text(s.search),
              ),
            ],
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.stockSoldRemaining,
          subtitle: s.stockSoldRemainingHint,
          child: Text(
            s.stockSoldRemainingExplainer,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 12),
        ReportTotalsCard(
          title: s.stockSoldRemaining,
          subtitle: s.stockSoldRemainingHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.openingStock,
              value: Formatters.integer(asDouble(totals['opening'])),
            ),
            ReportKeyValueRow(
              label: s.receivedStock,
              value: Formatters.integer(asDouble(totals['inQty'])),
            ),
            ReportKeyValueRow(
              label: s.soldStock,
              value: Formatters.integer(asDouble(totals['sold'])),
            ),
            ReportKeyValueRow(
              label: s.otherOut,
              value: Formatters.integer(asDouble(totals['outOther'])),
            ),
            ReportKeyValueRow(
              label: s.remainingStock,
              value: Formatters.integer(asDouble(totals['remaining'])),
              emphasise: true,
            ),
          ],
        ),
        if (byWarehouse.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          SectionCard(
            title: s.byWarehouse,
            subtitle: s.stockSoldRemainingHint,
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columnSpacing: 18,
                columns: <DataColumn>[
                  DataColumn(label: Text(s.warehouse)),
                  DataColumn(label: Text(s.products), numeric: true),
                  DataColumn(label: Text(s.openingStock), numeric: true),
                  DataColumn(label: Text(s.receivedStock), numeric: true),
                  DataColumn(label: Text(s.soldStock), numeric: true),
                  DataColumn(label: Text(s.otherOut), numeric: true),
                  DataColumn(label: Text(s.remainingStock), numeric: true),
                ],
                rows: <DataRow>[
                  for (final row in byWarehouse)
                    DataRow(
                      cells: <DataCell>[
                        DataCell(
                          SizedBox(
                            width: 200,
                            child: Text(
                              asString(row['warehouse']),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            Formatters.integer(asInt(row['products'])),
                            textAlign: TextAlign.end,
                          ),
                        ),
                        DataCell(_qty(row['opening'])),
                        DataCell(_qty(row['inQty'])),
                        DataCell(_qty(row['sold'])),
                        DataCell(_qty(row['outOther'])),
                        DataCell(_qty(row['remaining'], bold: true)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: s.stockSoldRemaining,
          subtitle: s.stockSoldRemainingHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 16,
              columns: <DataColumn>[
                DataColumn(label: Text(s.warehouse)),
                DataColumn(label: Text(s.product)),
                DataColumn(label: Text(s.category)),
                DataColumn(label: Text(s.openingStock), numeric: true),
                DataColumn(label: Text(s.receivedStock), numeric: true),
                DataColumn(label: Text(s.soldStock), numeric: true),
                DataColumn(label: Text(s.otherOut), numeric: true),
                DataColumn(label: Text(s.remainingStock), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 160,
                          child: Text(
                            asString(row['warehouse']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 230,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                asString(row['product']),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                asString(row['sku'], fallback: ''),
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: Text(
                            asString(row['category'], fallback: '—'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(_qty(row['opening'])),
                      DataCell(_qty(row['inQty'])),
                      DataCell(_qty(row['sold'], bold: true)),
                      DataCell(_qty(row['outOther'])),
                      DataCell(_qty(row['remaining'], bold: true, negative: true)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _qty(
    dynamic value, {
    bool bold = false,
    bool negative = false,
  }) {
    return Text(
      Formatters.integer(asDouble(value)),
      textAlign: TextAlign.end,
      style: TextStyle(
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        color: negative && asDouble(value) < 0
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    );
  }
}
