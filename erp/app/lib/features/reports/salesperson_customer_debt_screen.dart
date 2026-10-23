import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../state/reports_controller.dart';
import '../../state/salespeople_controller.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// A salesperson's debt as a classic ledger table:
/// `# | customer | previous | debit | credit | balance`.
class SalespersonCustomerDebtScreen extends StatefulWidget {
  const SalespersonCustomerDebtScreen({super.key, this.initialSalespersonId});

  final String? initialSalespersonId;

  @override
  State<SalespersonCustomerDebtScreen> createState() =>
      _SalespersonCustomerDebtScreenState();
}

class _SalespersonCustomerDebtScreenState
    extends State<SalespersonCustomerDebtScreen> {
  DateTime? _from;
  DateTime? _to;
  String? _salespersonId;

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _salespersonId = widget.initialSalespersonId ??
        (session.isSalesperson ? session.user?.id : null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalespeopleController>().ensureLoaded();
      if (_salespersonId != null) _reload();
    });
  }

  Future<void> _reload() async {
    final id = _salespersonId;
    final controller = context.read<ReportsController>();
    if (id == null || id.isEmpty) return;
    await controller.loadSalespersonCustomerDebt(
      salespersonId: id,
      from: _from,
      to: _to,
    );
  }

  void _apply(DateTime? from, DateTime? to, String? id) {
    setState(() {
      _from = from;
      _to = to;
      _salespersonId = id;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final salespeople = context.watch<SalespeopleController>().salespeople;
    final data = controller.salespersonCustomerDebt;
    final person = asMap(data['salesperson']);
    final totals = asMap(data['totals']);
    final rows = asMapList(data['rows']);
    final selectedId = _salespersonId;

    return ReportAsyncSection(
      loading: controller.loadingSalespersonCustomerDebt,
      error: controller.salespersonCustomerDebtError,
      isEmpty: selectedId == null || rows.isEmpty,
      emptyTitle:
          selectedId == null ? s.pickSalespersonFirst : s.noDataForFilters,
      onRetry: _reload,
      header: ReportHeader(
        onPrint: selectedId == null
            ? null
            : () => PrintService.printSalespersonCustomerDebt(
                  context,
                  selectedId,
                  from: _from,
                  to: _to,
                ),
        filters: <Widget>[
          DateRangeButton(
            from: _from,
            to: _to,
            onChanged: (from, to) => _apply(from, to, _salespersonId),
          ),
          const SizedBox(width: 10),
          if (!context.watch<Session>().isSalesperson) AppSelectField<String?>(
            label: s.salesperson,
            value: _salespersonId,
            prefixIcon: Icons.support_agent_outlined,
            options: <SelectOption<String?>>[
              for (final person in salespeople)
                SelectOption<String?>(person.id, person.name),
            ],
            onChanged: (value) => _apply(_from, _to, value),
          ),
        ],
      ),
      children: <Widget>[
        if (person.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              asString(person['name']),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        if (rows.isNotEmpty)
          SectionCard(
            title: s.salespersonCustomerDebt,
            subtitle: s.lineCount(rows.length),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: _DebtTable(rows: rows, totals: totals),
          ),
      ],
    );
  }
}

/// Horizontally scrollable ledger table with a totals footer.
class _DebtTable extends StatelessWidget {
  const _DebtTable({required this.rows, required this.totals});

  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> totals;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.outline,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width - 48,
        ),
        child: DataTable(
          headingTextStyle: headerStyle,
          dataTextStyle: theme.textTheme.bodyMedium,
          columnSpacing: 18,
          columns: <DataColumn>[
            DataColumn(label: Text('#', style: headerStyle)),
            DataColumn(label: Text(s.customer, style: headerStyle)),
            DataColumn(
              label: Text(s.previousBalance, style: headerStyle),
              numeric: true,
            ),
            DataColumn(label: Text(s.debit, style: headerStyle), numeric: true),
            DataColumn(label: Text(s.credit, style: headerStyle), numeric: true),
            DataColumn(
              label: Text(s.balance, style: headerStyle),
              numeric: true,
            ),
          ],
          rows: <DataRow>[
            for (var index = 0; index < rows.length; index++)
              DataRow(
                cells: <DataCell>[
                  DataCell(Text('${index + 1}')),
                  DataCell(Text(asString(rows[index]['customer']))),
                  DataCell(MoneyText(asDouble(rows[index]['previous']))),
                  DataCell(MoneyText(asDouble(rows[index]['debit']))),
                  DataCell(MoneyText(asDouble(rows[index]['credit']))),
                  DataCell(
                    MoneyText(
                      asDouble(rows[index]['balance']),
                      colorNegative: true,
                    ),
                  ),
                ],
              ),
            DataRow(
              color: WidgetStatePropertyAll<Color>(
                theme.colorScheme.surfaceContainerHighest,
              ),
              cells: <DataCell>[
                const DataCell(Text('')),
                DataCell(
                  Text(
                    s.total,
                    style: headerStyle,
                  ),
                ),
                DataCell(MoneyText(asDouble(totals['previous']))),
                DataCell(MoneyText(asDouble(totals['debit']))),
                DataCell(MoneyText(asDouble(totals['credit']))),
                DataCell(
                  MoneyText(
                    asDouble(totals['balance']),
                    colorNegative: true,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
