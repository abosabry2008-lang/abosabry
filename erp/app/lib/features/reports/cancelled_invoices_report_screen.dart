import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Invoices that were voided, with the cancellation date and the original
/// issue date. Filtering is by cancellation date.
class CancelledInvoicesReportScreen extends StatefulWidget {
  const CancelledInvoicesReportScreen({super.key});

  @override
  State<CancelledInvoicesReportScreen> createState() =>
      _CancelledInvoicesReportScreenState();
}

class _CancelledInvoicesReportScreenState
    extends State<CancelledInvoicesReportScreen> {
  DateTime? _from;
  DateTime? _to;
  String _search = '';
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
            '/reports/cancelled-invoices',
            query: <String, dynamic>{
              if (_from != null) 'from': _from!.toUtc().toIso8601String(),
              if (_to != null) 'to': Formatters.isoRangeEnd(_to!),
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
    final rows = asMapList(_data['rows']);
    final totals = asMap(_data['totals']);

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noCancelledInvoices,
      emptyIcon: Icons.block_outlined,
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
          Row(
            children: <Widget>[
              Expanded(
                child: AppSearchField(
                  hintText: s.searchCancelledInvoicesHint,
                  initialValue: _search,
                  onChanged: (value) {
                    setState(() => _search = value);
                  },
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
          title: s.cancelledInvoices,
          subtitle: s.cancelledInvoicesHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.invoices,
              value: Formatters.integer(asDouble(totals['count'])),
            ),
            ReportKeyValueRow(
              label: s.total,
              amount: asDouble(totals['total']),
              emphasise: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.cancelledInvoices,
          subtitle: s.invoiceCountLabel('${rows.length}'),
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 18,
              columns: <DataColumn>[
                DataColumn(label: Text(s.numberLabel)),
                DataColumn(label: Text(s.date)),
                DataColumn(label: Text(s.cancellationDate)),
                DataColumn(label: Text(s.customer)),
                DataColumn(label: Text(s.total), numeric: true),
                DataColumn(label: Text(s.notes)),
              ],
              rows: <DataRow>[
                for (final row in rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(Text(asString(row['number']))),
                      DataCell(
                        Text(Formatters.date(asDate(row['issueDate']))),
                      ),
                      DataCell(
                        Text(Formatters.date(asDate(row['updatedAt']))),
                      ),
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(
                            asString(
                              asMap(row['customer'])['name'],
                              fallback: s.walkInCustomer,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        MoneyText(
                          asDouble(row['total']),
                          colorNegative: true,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 240,
                          child: Text(
                            asString(row['notes'], fallback: '—'),
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
