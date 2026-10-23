import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = context.read<Session>();
      if (session.isSalesperson) {
        setState(() => _salespersonId = session.user?.id);
      }
      context.read<SalespeopleController>().ensureLoaded();
    });
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
                if (value != null) setState(() => _date = value);
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
                onChanged: (value) => setState(() => _salespersonId = value),
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
            ],
          ),
        ),
      ],
    );
  }
}
