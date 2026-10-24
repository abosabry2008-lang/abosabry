import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// How a column should be formatted.
enum ReportValue {
  text,
  money,
  integer,
  date,
  status,
}

class ReportColumn {
  const ReportColumn(this.key, this.label, {this.value = ReportValue.text});

  final String key;
  final String label;
  final ReportValue value;
}

class ReportTotal {
  const ReportTotal(this.key, this.label, {this.money = true});

  final String key;
  final String label;
  final bool money;
}

/// A config-driven report page. One widget renders every "extra" report from
/// the backend's `{ totals, rows }` shape, so adding a report is a matter of
/// describing its columns instead of writing another screen.
class ExtraReportScreen extends StatefulWidget {
  const ExtraReportScreen({
    super.key,
    required this.title,
    required this.path,
    required this.columns,
    this.totals = const <ReportTotal>[],
    this.dateRange = true,
    this.typeFilter = false,
    this.daysSelector = false,
    this.extraQuery = const <String, dynamic>{},
  });

  final String title;
  final String path;
  final List<ReportColumn> columns;
  final List<ReportTotal> totals;
  final bool dateRange;

  /// Shows customer / supplier return chips and sends `type`.
  final bool typeFilter;

  /// Shows a 30/60/90/180-day selector for the dead-stock report.
  final bool daysSelector;
  final Map<String, dynamic> extraQuery;

  @override
  State<ExtraReportScreen> createState() => _ExtraReportScreenState();
}

class _ExtraReportScreenState extends State<ExtraReportScreen> {
  DateTime? _from;
  DateTime? _to;
  String _type = '';
  int _days = 90;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.getObject(
            widget.path,
            query: <String, dynamic>{
              ...widget.extraQuery,
              if (widget.dateRange && _from != null)
                'from': _from!.toUtc().toIso8601String(),
              if (widget.dateRange && _to != null) 'to': Formatters.isoRangeEnd(_to!),
              if (widget.typeFilter && _type.isNotEmpty) 'type': _type,
              if (widget.daysSelector) 'days': _days,
            },
          );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (exception) {
      if (!mounted) return;
      setState(() {
        _error = exception.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.s.couldNotLoadReport;        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final rows = asMapList(_data['rows']);
    final totals = asMap(_data['totals']);

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noDataForFilters,
      emptyIcon: Icons.insights_outlined,
      onRetry: _load,
      header: ReportHeader(
        filters: <Widget>[
          if (widget.dateRange)
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
          if (widget.typeFilter) ...<Widget>[
            ChoiceChip(
              label: Text(s.allTypes),
              selected: _type.isEmpty,
              onSelected: (_) {
                setState(() => _type = '');
                _load();
              },
            ),
            ChoiceChip(
              label: Text(s.customerReturns),
              selected: _type == 'CUSTOMER_RETURN',
              onSelected: (_) {
                setState(() => _type = 'CUSTOMER_RETURN');
                _load();
              },
            ),
            ChoiceChip(
              label: Text(s.supplierReturns),
              selected: _type == 'SUPPLIER_RETURN',
              onSelected: (_) {
                setState(() => _type = 'SUPPLIER_RETURN');
                _load();
              },
            ),
          ],
          if (widget.daysSelector)
            DropdownButton<int>(
              value: _days,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _days = value);
                _load();
              },
              items: const <int>[30, 60, 90, 180, 365]
                  .map(
                    (days) => DropdownMenuItem<int>(
                      value: days,
                      child: Text('$days ${s.days}'),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
      children: <Widget>[
        if (widget.totals.isNotEmpty)
          ReportTotalsCard(
            title: widget.title,
            rows: <Widget>[
              for (final total in widget.totals)
                ReportKeyValueRow(
                  label: total.label,
                  value: total.money
                      ? null
                      : Formatters.integer(asDouble(totals[total.key])),
                  amount:
                      total.money ? asDouble(totals[total.key]) : null,
                ),
            ],
          ),
        const SizedBox(height: 12),
        _ReportTable(columns: widget.columns, rows: rows),
      ],
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.columns, required this.rows});

  final List<ReportColumn> columns;
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SectionCard(
      title: s.report,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll<Color>(
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          columnSpacing: 20,
          horizontalMargin: 8,
          columns: columns
              .map(
                (column) => DataColumn(
                  label: Text(
                    column.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  numeric: column.value == ReportValue.money ||
                      column.value == ReportValue.integer,
                ),
              )
              .toList(),
          rows: rows
              .map(
                (row) => DataRow(
                  cells: columns
                      .map(
                        (column) => DataCell(
                          _cell(context, column, row[column.key]),
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, ReportColumn column, dynamic value) {
    final numeric = column.value == ReportValue.money ||
        column.value == ReportValue.integer;
    final align = numeric ? TextAlign.end : TextAlign.start;
    switch (column.value) {
      case ReportValue.money:
        return Align(
          alignment: Alignment.centerRight,
          child: MoneyText(asDouble(value)),
        );
      case ReportValue.integer:
        return Text(
          Formatters.integer(asDouble(value)),
          textAlign: align,
        );
      case ReportValue.date:
        return Text(
          Formatters.date(DateTime.tryParse('$value')?.toLocal()),
          textAlign: align,
        );
      case ReportValue.status:
        return Text(context.s.status('$value'), textAlign: align);
      case ReportValue.text:
        final text = '$value';
        return Text(
          text.trim().isEmpty ? '—' : text,
          textAlign: align,
        );
    }
  }
}
