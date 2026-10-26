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

/// Active customers with no invoice for N days, optionally for one salesperson.
class DormantCustomersScreen extends StatefulWidget {
  const DormantCustomersScreen({super.key});

  @override
  State<DormantCustomersScreen> createState() => _DormantCustomersScreenState();
}

class _DormantCustomersScreenState extends State<DormantCustomersScreen> {
  int _days = 90;
  String? _salespersonId;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalespeopleController>().ensureLoaded();
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.getObject(
            '/reports/dormant-customers',
            query: <String, dynamic>{
              'days': _days,
              if (_salespersonId != null && _salespersonId!.isNotEmpty)
                'salespersonId': _salespersonId,
            },
          );
      if (!mounted) return;
      setState(() => _rows = asMapList(data['rows']));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final salespeople = context.watch<SalespeopleController>().salespeople;
    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: _rows.isEmpty,
      emptyTitle: s.noDataForFilters,
      emptyIcon: Icons.person_off_outlined,
      onRetry: _load,
      header: ReportHeader(
        filters: <Widget>[
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
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.dormantCustomers,
          subtitle: s.dormantCustomersHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 20,
              columns: <DataColumn>[
                DataColumn(label: Text(s.customer)),
                DataColumn(label: Text(s.salesperson)),
                DataColumn(label: Text(s.lastInvoice)),
                DataColumn(label: Text(s.days), numeric: true),
                DataColumn(label: Text(s.balance), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in _rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 240,
                          child: Text(asString(row['name'])),
                        ),
                      ),
                      DataCell(
                        Text(
                          asStringOrNull(row['salesperson']) ?? s.unassigned,
                        ),
                      ),
                      DataCell(
                        Text(
                          asStringOrNull(row['lastInvoiceAt']) == null
                              ? s.neverInvoiced
                              : Formatters.date(
                                  asDate(row['lastInvoiceAt']),
                                ),
                        ),
                      ),
                      DataCell(
                        Text(
                          row['daysSince'] == null
                              ? '—'
                              : Formatters.integer(
                                  asDouble(row['daysSince']),
                                ),
                          textAlign: TextAlign.end,
                        ),
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
