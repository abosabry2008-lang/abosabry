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

/// Stocktake sessions: counted quantities against the system balance.
class CycleCountReportScreen extends StatefulWidget {
  const CycleCountReportScreen({super.key});

  @override
  State<CycleCountReportScreen> createState() => _CycleCountReportScreenState();
}

class _CycleCountReportScreenState extends State<CycleCountReportScreen> {
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
            '/reports/cycle-counts',
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
    final sessions = asMapList(_data['sessions']);
    final totals = asMap(_data['totals']);
    final warehouses = context.watch<WarehousesController>().items;

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noCycleCounts,
      emptyIcon: Icons.fact_check_outlined,
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
        SectionCard(
          title: s.cycleCountReport,
          subtitle: s.cycleCountReportHint,
          child: Text(
            s.cycleCountReportExplainer,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 12),
        ReportTotalsCard(
          title: s.cycleCountReport,
          subtitle: s.cycleCountReportHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.sessionLabel,
              value: Formatters.integer(asInt(totals['sessions'])),
            ),
            ReportKeyValueRow(
              label: s.countedItems,
              value: Formatters.integer(asInt(totals['items'])),
            ),
            ReportKeyValueRow(
              label: s.shortageQty,
              value: Formatters.integer(asDouble(totals['shortageQty'])),
            ),
            ReportKeyValueRow(
              label: s.surplus,
              value: Formatters.integer(asDouble(totals['surplusQty'])),
            ),
            ReportKeyValueRow(
              label: s.stocktakeValue,
              amount: asDouble(totals['value']),
              emphasise: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.sessionLabel,
          subtitle: s.cycleCountReportHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 16,
              columns: <DataColumn>[
                DataColumn(label: Text(s.numberLabel)),
                DataColumn(label: Text(s.date)),
                DataColumn(label: Text(s.warehouse)),
                DataColumn(label: Text(s.countedItems), numeric: true),
                DataColumn(label: Text(s.shortageQty), numeric: true),
                DataColumn(label: Text(s.surplus), numeric: true),
                DataColumn(label: Text(s.netAdjustment), numeric: true),
                DataColumn(label: Text(s.stocktakeValue), numeric: true),
              ],
              rows: <DataRow>[
                for (final session in sessions)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: Text(
                            asString(session['reference']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(Formatters.date(asDate(session['date'])))),
                      DataCell(
                        SizedBox(
                          width: 160,
                          child: Text(
                            '${asString(session['warehouse'], fallback: '—')} · ${asString(session['location'], fallback: '')}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asInt(session['items'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(session['shortageQty'])),
                          textAlign: TextAlign.end,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(session['surplusQty'])),
                          textAlign: TextAlign.end,
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(session['netQty'])),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(MoneyText(asDouble(session['value']))),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.countedItems,
          subtitle: s.cycleCountReportHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 16,
              columns: <DataColumn>[
                DataColumn(label: Text(s.date)),
                DataColumn(label: Text(s.numberLabel)),
                DataColumn(label: Text(s.warehouse)),
                DataColumn(label: Text(s.product)),
                DataColumn(label: Text(s.systemQty), numeric: true),
                DataColumn(label: Text(s.counted), numeric: true),
                DataColumn(label: Text(s.differenceLabel), numeric: true),
                DataColumn(label: Text(s.costValue), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(Text(Formatters.date(asDate(row['date'])))),
                      DataCell(
                        SizedBox(
                          width: 130,
                          child: Text(
                            asString(row['reference']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: Text(
                            asString(row['warehouse'], fallback: '—'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 220,
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
                          Formatters.integer(asDouble(row['systemQty'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(row['countedQty'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(row['difference'])),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: asDouble(row['difference']) < 0
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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
