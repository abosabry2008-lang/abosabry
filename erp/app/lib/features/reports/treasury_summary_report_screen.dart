import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/cash_box.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// A comprehensive cash-treasury report: opening/in/out/closing per box,
/// a breakdown by movement type and the detailed movements.
class TreasurySummaryReportScreen extends StatefulWidget {
  const TreasurySummaryReportScreen({super.key});

  @override
  State<TreasurySummaryReportScreen> createState() =>
      _TreasurySummaryReportScreenState();
}

class _TreasurySummaryReportScreenState
    extends State<TreasurySummaryReportScreen> {
  DateTime? _from;
  DateTime? _to;
  String? _boxId;
  List<CashBox> _boxes = <CashBox>[];
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoxes());
  }

  Future<void> _loadBoxes() async {
    try {
      final rows = await context.read<Session>().api.getList('/treasury/boxes');
      if (!mounted) return;
      setState(() => _boxes = rows.map(CashBox.fromJson).toList());
    } catch (_) {
      // The report can still load without the box filter.
    }
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.getObject(
            '/reports/treasury-summary',
            query: <String, dynamic>{
              if (_from != null) 'from': _from!.toUtc().toIso8601String(),
              if (_to != null) 'to': Formatters.isoRangeEnd(_to!),
              if (_boxId != null) 'cashBoxId': _boxId,
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
    final boxes = asMapList(_data['boxes']);
    final rows = asMapList(_data['rows']);
    final breakdown = asMapList(_data['breakdown']);
    final totals = asMap(_data['totals']);
    final theme = Theme.of(context);

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: boxes.isEmpty,
      emptyTitle: s.noCashBoxes,
      emptyIcon: Icons.account_balance_wallet_outlined,
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
            label: s.cashBox,
            value: _boxId ?? '',
            hint: s.allBoxes,
            prefixIcon: Icons.account_balance_wallet_outlined,
            options: <SelectOption<String>>[
              SelectOption<String>('', s.allBoxes),
              ..._boxes.map(
                (box) => SelectOption<String>(box.id, box.name),
              ),
            ],
            onChanged: (value) {
              setState(
                () => _boxId =
                    (value == null || value.isEmpty) ? null : value,
              );
              _load();
            },
          ),
          FilledButton.tonalIcon(
            onPressed: _load,
            icon: const Icon(Icons.search),
            label: Text(s.search),
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.treasurySummary,
          subtitle: s.treasurySummaryHint,
          child: Text(
            s.treasurySummaryExplainer,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 12),
        _KpiGrid(totals: totals),
        const SizedBox(height: 12),
        SectionCard(
          title: s.boxMovements,
          subtitle: s.cashBoxes,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 18,
              columns: <DataColumn>[
                DataColumn(label: Text(s.cashBox)),
                DataColumn(label: Text(s.openingBalance), numeric: true),
                DataColumn(label: Text(s.inShort), numeric: true),
                DataColumn(label: Text(s.outShort), numeric: true),
                DataColumn(label: Text(s.closingBalance), numeric: true),
                DataColumn(label: Text(s.movementCount), numeric: true),
              ],
              rows: <DataRow>[
                for (final box in boxes)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 200,
                          child: Text(
                            asString(box['name']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(MoneyText(asDouble(box['opening']))),
                      DataCell(
                        MoneyText(
                          asDouble(box['in']),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DataCell(
                        MoneyText(
                          asDouble(box['out']),
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DataCell(
                        MoneyText(
                          asDouble(box['closing']),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asInt(box['movements'])),
                          textAlign: TextAlign.end,
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
          title: s.byMovementType,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 18,
              columns: <DataColumn>[
                DataColumn(label: Text(s.type)),
                DataColumn(label: Text(s.inShort), numeric: true),
                DataColumn(label: Text(s.outShort), numeric: true),
                DataColumn(label: Text(s.netMovement), numeric: true),
                DataColumn(label: Text(s.movementCount), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in breakdown)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 210,
                          child: Text(s.status(asString(row['type']))),
                        ),
                      ),
                      DataCell(MoneyText(asDouble(row['in']))),
                      DataCell(MoneyText(asDouble(row['out']))),
                      DataCell(
                        MoneyText(
                          asDouble(row['net']),
                          colorNegative: true,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asInt(row['count'])),
                          textAlign: TextAlign.end,
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
          title: s.treasuryMovements,
          subtitle: s.treasurySummaryHint,
          padding: EdgeInsets.zero,
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.noDataForFilters),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    showCheckboxColumn: false,
                    columnSpacing: 16,
                    columns: <DataColumn>[
                      DataColumn(label: Text(s.date)),
                      DataColumn(label: Text(s.cashBox)),
                      DataColumn(label: Text(s.type)),
                      DataColumn(label: Text(s.numberLabel)),
                      DataColumn(label: Text(s.description)),
                      DataColumn(label: Text(s.inShort), numeric: true),
                      DataColumn(label: Text(s.outShort), numeric: true),
                      DataColumn(label: Text(s.balance), numeric: true),
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
                                  asString(row['boxName']),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(s.status(asString(row['type']))),
                            ),
                            DataCell(Text(asString(row['number'], fallback: '—'))),
                            DataCell(
                              SizedBox(
                                width: 280,
                                child: Text(
                                  asString(row['description'], fallback: '—'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              asString(row['direction']) == 'IN'
                                  ? MoneyText(asDouble(row['amount']))
                                  : const Text(''),
                            ),
                            DataCell(
                              asString(row['direction']) == 'OUT'
                                  ? MoneyText(asDouble(row['amount']))
                                  : const Text(''),
                            ),
                            DataCell(MoneyText(asDouble(row['balance']))),
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

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.totals});

  final Map<String, dynamic> totals;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final tiles = <Widget>[
      _Kpi(label: s.openingBalance, amount: asDouble(totals['opening'])),
      _Kpi(
        label: s.totalIn,
        amount: asDouble(totals['in']),
        color: const Color(0xFF107E3E),
      ),
      _Kpi(
        label: s.totalOut,
        amount: asDouble(totals['out']),
        color: Theme.of(context).colorScheme.error,
      ),
      _Kpi(
        label: s.closingBalance,
        amount: asDouble(totals['closing']),
        emphasise: true,
      ),
      _Kpi(
        label: s.movementCount,
        value: Formatters.integer(asInt(totals['movements'])),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 5
            : constraints.maxWidth >= 520
                ? 3
                : 2;
        const gap = 8.0;
        final width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    this.amount,
    this.value,
    this.color,
    this.emphasise = false,
  });

  final String label;
  final double? amount;
  final String? value;
  final Color? color;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
          const SizedBox(height: 3),
          if (value != null)
            Text(
              value!,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            )
          else
            MoneyText(
              amount ?? 0,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}
