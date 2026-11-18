import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../state/warehouses_controller.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Manual stock adjustments with quantities, cost and value.
class StockAdjustmentsScreen extends StatefulWidget {
  const StockAdjustmentsScreen({super.key});

  @override
  State<StockAdjustmentsScreen> createState() => _StockAdjustmentsScreenState();
}

class _StockAdjustmentsScreenState extends State<StockAdjustmentsScreen> {
  DateTime? _from;
  DateTime? _to;
  String? _warehouseId;
  String _search = '';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WarehousesController>().ensureLoaded();
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
            '/reports/stock-adjustments',
            query: <String, dynamic>{
              if (_from != null) 'from': _from!.toUtc().toIso8601String(),
              if (_to != null) 'to': Formatters.isoRangeEnd(_to!),
              if (_warehouseId != null) 'warehouseId': _warehouseId,
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

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noStockAdjustments,
      emptyIcon: Icons.tune,
      onRetry: _load,
      header: ReportHeader(
        filters: <Widget>[
          DateRangeButton(
            from: _from,
            to: _to,
            onChanged: (from, to) {
              setState(() {
                _from = from;
                _to = to;
              });
              _load();
            },
          ),
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
        ReportTotalsCard(
          title: s.stockAdjustments,
          subtitle: s.stockAdjustmentsHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.countLabel,
              value: Formatters.integer(asInt(totals['count'])),
            ),
            ReportKeyValueRow(
              label: s.inShort,
              value: Formatters.integer(asDouble(totals['inQty'])),
            ),
            ReportKeyValueRow(
              label: s.outShort,
              value: Formatters.integer(asDouble(totals['outQty'])),
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
          title: s.stockAdjustments,
          subtitle: s.stockAdjustmentsHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 16,
              columns: <DataColumn>[
                DataColumn(label: Text(s.date)),
                DataColumn(label: Text(s.warehouse)),
                DataColumn(label: Text(s.product)),
                DataColumn(label: Text(s.quantity), numeric: true),
                DataColumn(label: Text(s.costPrice), numeric: true),
                DataColumn(label: Text(s.costValue), numeric: true),
                DataColumn(label: Text(s.notes)),
              ],
              rows: <DataRow>[
                for (final row in rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(Text(Formatters.date(asDate(row['date'])))),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Text(
                            asString(row['warehouse'], fallback: '—'),
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
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(row['quantity'])),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: asDouble(row['quantity']) < 0
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      DataCell(MoneyText(asDouble(row['unitCost']))),
                      DataCell(MoneyText(asDouble(row['value']))),
                      DataCell(
                        SizedBox(
                          width: 240,
                          child: Text(
                            asString(row['note'], fallback: '—'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
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
