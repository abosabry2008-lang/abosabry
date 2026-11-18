import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../state/categories_controller.dart';
import '../../state/warehouses_controller.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Stock levels that fell below zero, with the value needed to correct them.
class NegativeStockScreen extends StatefulWidget {
  const NegativeStockScreen({super.key});

  @override
  State<NegativeStockScreen> createState() => _NegativeStockScreenState();
}

class _NegativeStockScreenState extends State<NegativeStockScreen> {
  String? _warehouseId;
  String? _categoryId;
  String _search = '';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
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
            '/reports/negative-stock',
            query: <String, dynamic>{
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
    final totals = asMap(_data['totals']);
    final warehouses = context.watch<WarehousesController>().items;
    final categories = context.watch<CategoriesController>().items;

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noNegativeStock,
      emptyIcon: Icons.check_circle_outline,
      onRetry: _load,
      header: ReportHeader(
        filters: <Widget>[
          AppSelectField<String>(
            label: s.warehouse,
            value: _warehouseId ?? '',
            hint: s.allWarehouses,
            options: <SelectOption<String>>[
              SelectOption<String>('', s.allWarehouses),
              ...warehouses.map(
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
              _load();
            },
          ),
          AppSelectField<String>(
            label: s.category,
            value: _categoryId ?? '',
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
          title: s.negativeStock,
          subtitle: s.negativeStockHint,
          child: Text(s.negativeStockExplainer, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 12),
        ReportTotalsCard(
          title: s.negativeStock,
          subtitle: s.negativeStockHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.countLabel,
              value: Formatters.integer(asInt(totals['items'])),
            ),
            ReportKeyValueRow(
              label: s.quantity,
              value: Formatters.integer(asDouble(totals['quantity'])),
            ),
            ReportKeyValueRow(
              label: s.costValue,
              amount: asDouble(totals['value']),
              emphasise: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.negativeStock,
          subtitle: s.negativeStockHint,
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
                DataColumn(label: Text(s.quantity), numeric: true),
                DataColumn(label: Text(s.costPrice), numeric: true),
                DataColumn(label: Text(s.costValue), numeric: true),
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
                          width: 240,
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
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(row['quantity'])),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      DataCell(MoneyText(asDouble(row['unitCost']))),
                      DataCell(MoneyText(asDouble(row['value']))),
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
