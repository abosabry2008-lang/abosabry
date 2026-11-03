import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../state/salespeople_controller.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Debtor customers who recorded no collection on the selected day.
class CustomersNotPaidScreen extends StatefulWidget {
  const CustomersNotPaidScreen({super.key});

  @override
  State<CustomersNotPaidScreen> createState() => _CustomersNotPaidScreenState();
}

class _CustomersNotPaidScreenState extends State<CustomersNotPaidScreen> {
  late DateTime _day;
  String _search = '';
  String? _salespersonId;
  bool _onlyWithInvoices = false;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalespeopleController>().ensureLoaded();
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
            '/reports/customers-not-paid',
            query: <String, dynamic>{
              'date': Formatters.isoDate(_day),
              if (_search.trim().isNotEmpty) 'search': _search.trim(),
              if (_salespersonId != null) 'salespersonId': _salespersonId,
              if (_onlyWithInvoices) 'onlyWithInvoices': 'true',
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
    final bySalesperson = asMapList(_data['bySalesperson']);
    final salespeople = context.watch<SalespeopleController>().salespeople;
    final isSalesperson = context.watch<Session>().isSalesperson;

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noCustomersNotPaid,
      emptyIcon: Icons.check_circle_outline,
      onRetry: _load,
      header: ReportHeader(
        filters: <Widget>[
          SizedBox(
            width: 190,
            child: AppDateField(
              label: s.date,
              value: _day,
              clearable: false,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _day = value);
                _load();
              },
            ),
          ),
          if (!isSalesperson)
            AppSelectField<String?>(
              label: s.salesperson,
              value: _salespersonId,
              prefixIcon: Icons.support_agent_outlined,
              options: <SelectOption<String?>>[
                SelectOption<String?>(null, s.allSalespeople),
                for (final person in salespeople)
                  SelectOption<String?>(person.id, person.name),
              ],
              onChanged: (value) {
                setState(() => _salespersonId = value);
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
            selected: _onlyWithInvoices,
            label: Text(s.onlyWithInvoicesToday),
            onSelected: (value) {
              setState(() => _onlyWithInvoices = value);
              _load();
            },
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.customersNotPaid,
          subtitle: s.customersNotPaidHint,
          child: Text(
            s.customersNotPaidExplainer,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 12),
        ReportTotalsCard(
          title: s.customersNotPaid,
          subtitle: s.customersNotPaidHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.countLabel,
              value: Formatters.integer(asInt(totals['customers'])),
            ),
            ReportKeyValueRow(
              label: s.todayInvoices,
              amount: asDouble(totals['invoiceTotal']),
            ),
            ReportKeyValueRow(
              label: s.invoiceCountHeader,
              value: Formatters.integer(asInt(totals['invoiceCount'])),
            ),
            ReportKeyValueRow(
              label: s.balance,
              amount: asDouble(totals['balance']),
              emphasise: true,
            ),
          ],
        ),
        if (bySalesperson.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          SectionCard(
            title: s.salesperson,
            subtitle: s.customersNotPaidHint,
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columnSpacing: 18,
                columns: <DataColumn>[
                  DataColumn(label: Text(s.salesperson)),
                  DataColumn(label: Text(s.countLabel), numeric: true),
                  DataColumn(label: Text(s.invoiceCountHeader), numeric: true),
                  DataColumn(label: Text(s.todayInvoices), numeric: true),
                  DataColumn(label: Text(s.balance), numeric: true),
                ],
                rows: <DataRow>[
                  for (final row in bySalesperson)
                    DataRow(
                      cells: <DataCell>[
                        DataCell(
                          SizedBox(
                            width: 200,
                            child: Text(
                              asString(
                                row['salesperson'],
                                fallback: s.noSalesperson,
                              ),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            Formatters.integer(asInt(row['customers'])),
                            textAlign: TextAlign.end,
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
                          MoneyText(
                            asDouble(row['balance']),
                            colorNegative: true,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
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
        const SizedBox(height: 12),
        SectionCard(
          title: s.customersNotPaid,
          subtitle: s.customersNotPaidHint,
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
                DataColumn(label: Text(s.todayInvoices), numeric: true),
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
                          width: 230,
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
}
