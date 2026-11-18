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
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Stock transfer vouchers between warehouses.
class StockTransfersScreen extends StatefulWidget {
  const StockTransfersScreen({super.key});

  @override
  State<StockTransfersScreen> createState() => _StockTransfersScreenState();
}

class _StockTransfersScreenState extends State<StockTransfersScreen> {
  DateTime? _from;
  DateTime? _to;
  String? _warehouseId;
  String _search = '';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];

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
            '/inventory/transfers',
            query: <String, dynamic>{
              if (_from != null) 'from': _from!.toUtc().toIso8601String(),
              if (_to != null) 'to': Formatters.isoRangeEnd(_to!),
              if (_warehouseId != null) 'warehouseId': _warehouseId,
              if (_search.trim().isNotEmpty) 'search': _search.trim(),
            },
          );
      if (!mounted) return;
      setState(() {
        _rows = asMapList(data['rows']);
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
    final warehouses = context.watch<WarehousesController>().items;
    final lineCount = _rows.fold<int>(
      0,
      (sum, row) => sum + asInt(row['lineCount']),
    );
    final totalBoxes = _rows.fold<double>(
      0,
      (sum, row) => sum + asDouble(row['totalBoxes']),
    );

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: _rows.isEmpty,
      emptyTitle: s.noStockTransfers,
      emptyIcon: Icons.swap_horiz,
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
          title: s.stockTransfersReport,
          subtitle: s.stockTransfersHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.countLabel,
              value: Formatters.integer(_rows.length),
            ),
            ReportKeyValueRow(
              label: s.transferItems,
              value: Formatters.integer(lineCount),
            ),
            ReportKeyValueRow(
              label: s.totalInBoxes,
              value: Formatters.integer(totalBoxes),
              emphasise: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.stockTransfersReport,
          subtitle: s.stockTransfersHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 16,
              columns: <DataColumn>[
                DataColumn(label: Text(s.numberLabel)),
                DataColumn(label: Text(s.date)),
                DataColumn(label: Text(s.from)),
                DataColumn(label: Text(s.to)),
                DataColumn(label: Text(s.transferItems), numeric: true),
                DataColumn(label: Text(s.totalInBoxes), numeric: true),
                DataColumn(label: Text(s.notes)),
              ],
              rows: <DataRow>[
                for (final row in _rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(Text(asString(row['number']))),
                      DataCell(Text(Formatters.date(asDate(row['date'])))),
                      DataCell(
                        SizedBox(
                          width: 160,
                          child: Text(
                            asString(asMap(row['fromWarehouse'])['name'], fallback: '—'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 160,
                          child: Text(
                            asString(asMap(row['toWarehouse'])['name'], fallback: '—'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asInt(row['lineCount'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(row['totalBoxes'])),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 220,
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
        const SizedBox(height: 12),
        SectionCard(
          title: s.transferItems,
          subtitle: s.stockTransfersHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 16,
              columns: <DataColumn>[
                DataColumn(label: Text(s.numberLabel)),
                DataColumn(label: Text(s.product)),
                DataColumn(label: Text(s.quantity), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in _rows)
                  for (final line in asMapList(row['lines']))
                    DataRow(
                      cells: <DataCell>[
                        DataCell(Text(asString(row['number']))),
                        DataCell(
                          SizedBox(
                            width: 260,
                            child: Text(
                              '${asString(line['name'])} · ${asString(line['sku'], fallback: '')}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            Formatters.integer(asDouble(line['boxes'])),
                            textAlign: TextAlign.end,
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
