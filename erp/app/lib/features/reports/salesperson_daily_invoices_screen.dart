import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../state/salespeople_controller.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Prints every issued invoice for one salesperson for a chosen day, each on
/// its own A5 page so the operator can hand them over.
class SalespersonDailyInvoicesScreen extends StatefulWidget {
  const SalespersonDailyInvoicesScreen({super.key});

  @override
  State<SalespersonDailyInvoicesScreen> createState() =>
      _SalespersonDailyInvoicesScreenState();
}

class _SalespersonDailyInvoicesScreenState
    extends State<SalespersonDailyInvoicesScreen> {
  late DateTime _date = DateTime.now();
  String? _salespersonId;
  List<Map<String, dynamic>> _invoices = <Map<String, dynamic>>[];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final session = context.read<Session>();
      if (session.isSalesperson) {
        setState(() => _salespersonId = session.user?.id);
      }
      await context.read<SalespeopleController>().ensureLoaded();
      if (!mounted) return;
      if (_salespersonId == null) {
        final people = context.read<SalespeopleController>().salespeople;
        if (people.isNotEmpty) {
          setState(() => _salespersonId = people.first.id);
        }
      }
      await _load();
    });
  }

  Future<void> _load() async {
    final id = _salespersonId;
    if (id == null) {
      setState(() => _invoices = <Map<String, dynamic>>[]);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final start = DateTime(_date.year, _date.month, _date.day);
    final end = DateTime(_date.year, _date.month, _date.day, 23, 59, 59, 999);
    try {
      final rows = await context.read<Session>().api.getList(
            '/invoices',
            query: <String, dynamic>{
              'from': start.toIso8601String(),
              'to': end.toIso8601String(),
              'salespersonId': id,
              'pageSize': 100,
            },
          );
      if (!mounted) return;
      setState(() {
        _invoices = rows
            .where(
              (row) => const <String>['ISSUED', 'PARTIALLY_PAID', 'PAID']
                  .contains(asString(row['status'])),
            )
            .toList();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _print() async {
    final id = _salespersonId;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.pickSalespersonFirst)),
      );
      return;
    }
    final start = DateTime(_date.year, _date.month, _date.day);
    final end = DateTime(_date.year, _date.month, _date.day, 23, 59, 59, 999);
    await PrintService.printSalespersonDailyInvoices(
      context,
      id,
      from: start,
      to: end,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = context.watch<Session>();
    final people = context.watch<SalespeopleController>().salespeople;
    return Column(
      children: <Widget>[
        ReportHeader(
          onPrint: _print,
          filters: <Widget>[
            AppDateField(
              label: s.date,
              value: _date,
              clearable: false,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _date = value);
                  _load();
                }
              },
            ),
            if (!session.isSalesperson)
              AppSelectField<String?>(
                label: s.salesperson,
                value: _salespersonId,
                hint: s.chooseSalesperson,
                prefixIcon: Icons.support_agent_outlined,
                options: <SelectOption<String?>>[
                  for (final person in people)
                    SelectOption<String?>(person.id, person.name),
                ],
                onChanged: (value) {
                  setState(() => _salespersonId = value);
                  _load();
                },
              ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
              SectionCard(
                title: s.dailyInvoicesPrint,
                subtitle: s.dailyInvoicesPrintHint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      s.dailyInvoicesA5Hint,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _salespersonId == null ? null : _print,
                      icon: const Icon(Icons.print_outlined),
                      label: Text(s.printAllInvoices),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: s.invoices,
                subtitle: s.invoiceCountLabel('${_invoices.length}'),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _error != null
                        ? Text(_error!)
                        : _invoices.isEmpty
                            ? Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(s.noDataForFilters),
                              )
                            : Column(
                                children: <Widget>[
                                  for (final invoice in _invoices)
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(asString(invoice['number'])),
                                      subtitle: Text(
                                        '${asString(asMap(invoice['customer'])['name'], fallback: s.walkInCustomer)}'
                                        ' · ${asString(invoice['status'])}',
                                      ),
                                      trailing: Text(
                                        asDouble(invoice['total']).toStringAsFixed(2),
                                      ),
                                    ),
                                ],
                              ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
