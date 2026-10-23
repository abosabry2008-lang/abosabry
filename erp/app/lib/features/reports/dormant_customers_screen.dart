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
          child: Column(
            children: <Widget>[
              for (final row in _rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(asString(row['name'])),
                  subtitle: Text(
                    <String>[
                      if (asStringOrNull(row['salesperson']) != null)
                        '${s.salesperson}: ${asString(row['salesperson'])}',
                      if (asStringOrNull(row['lastInvoiceAt']) == null)
                        s.neverInvoiced
                      else
                        '${s.lastInvoice}: ${Formatters.date(asDate(row['lastInvoiceAt']))}',
                      if (row['daysSince'] != null)
                        '${Formatters.integer(asDouble(row['daysSince']))} ${s.days}',
                    ].join(' · '),
                  ),
                  trailing: MoneyText(asDouble(row['balance'])),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
