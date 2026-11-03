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

/// Compares each customer's invoices with their collections for the selected
/// period, showing the collection rate and the remaining balance.
class CustomerDailyEvaluationScreen extends StatefulWidget {
  const CustomerDailyEvaluationScreen({super.key});

  @override
  State<CustomerDailyEvaluationScreen> createState() =>
      _CustomerDailyEvaluationScreenState();
}

class _CustomerDailyEvaluationScreenState
    extends State<CustomerDailyEvaluationScreen> {
  late DateTime _from;
  late DateTime _to;
  String _search = '';
  bool _includeAll = false;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _from = DateTime(today.year, today.month, today.day);
    _to = DateTime(today.year, today.month, today.day);
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
            '/reports/customer-daily-evaluation',
            query: <String, dynamic>{
              'from': _from.toUtc().toIso8601String(),
              'to': Formatters.isoRangeEnd(_to),
              if (_search.trim().isNotEmpty) 'search': _search.trim(),
              if (_includeAll) 'includeAll': 'true',
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
      emptyTitle: s.noCustomerActivity,
      emptyIcon: Icons.people_outline,
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
          Row(
            children: <Widget>[
              Expanded(
                child: AppSearchField(
                  hintText: s.searchCustomersHint,
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
          FilterChip(
            selected: _includeAll,
            label: Text(s.showAllCustomers),
            onSelected: (value) {
              setState(() => _includeAll = value);
              _load();
            },
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.customerDailyEvaluation,
          subtitle: s.customerDailyEvaluationHint,
          child: Text(
            s.customerDailyEvaluationExplainer,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 12),
        ReportTotalsCard(
          title: s.customerDailyEvaluation,
          subtitle: s.customerDailyEvaluationHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.countLabel,
              value: Formatters.integer(asInt(totals['customers'])),
            ),
            ReportKeyValueRow(
              label: s.invoices,
              amount: asDouble(totals['invoiceTotal']),
            ),
            ReportKeyValueRow(
              label: s.collections,
              amount: asDouble(totals['paidTotal']),
            ),
            ReportKeyValueRow(
              label: s.netMovement,
              amount: asDouble(totals['net']),
              emphasise: true,
            ),
            ReportKeyValueRow(
              label: s.collectionRate,
              value: _percent(asDouble(totals['collectionRate'])),
            ),
            ReportKeyValueRow(
              label: s.balance,
              amount: asDouble(totals['balance']),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.customerDailyEvaluation,
          subtitle: s.customerDailyEvaluationHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 16,
              columns: <DataColumn>[
                DataColumn(label: Text(s.customer)),
                DataColumn(label: Text(s.salesperson)),
                DataColumn(label: Text(s.invoiceCountHeader), numeric: true),
                DataColumn(label: Text(s.invoiceValueHeader), numeric: true),
                DataColumn(label: Text(s.paymentCountHeader), numeric: true),
                DataColumn(label: Text(s.paymentValueHeader), numeric: true),
                DataColumn(label: Text(s.netMovement), numeric: true),
                DataColumn(label: Text(s.collectionRate), numeric: true),
                DataColumn(label: Text(s.balance), numeric: true),
                DataColumn(label: Text(s.lastPayment)),
                DataColumn(label: Text(s.daysSinceLastPayment), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                asString(row['name']),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                [
                                  asString(row['code'], fallback: ''),
                                  asString(row['phone'], fallback: ''),
                                ].where((part) => part.isNotEmpty).join(' · '),
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Text(
                            asString(row['salesperson'], fallback: '—'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asInt(row['invoiceCount'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(MoneyText(asDouble(row['invoiceTotal']))),
                      DataCell(
                        Text(
                          Formatters.integer(asInt(row['paymentCount'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(MoneyText(asDouble(row['paidTotal']))),
                      DataCell(
                        MoneyText(
                          asDouble(row['net']),
                          colorNegative: true,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        Text(
                          row['collectionRate'] == null
                              ? '—'
                              : _percent(asDouble(row['collectionRate'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(
                        MoneyText(
                          asDouble(row['balance']),
                          colorNegative: true,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        Text(
                          asDate(row['lastPaymentAt']) == null
                              ? s.neverPaid
                              : Formatters.date(asDate(row['lastPaymentAt'])),
                        ),
                      ),
                      DataCell(
                        Text(
                          row['daysSinceLastPayment'] == null
                              ? '—'
                              : Formatters.integer(
                                  asInt(row['daysSinceLastPayment']),
                                ),
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

  String _percent(double value) => '${value.toStringAsFixed(1)}%';
}
