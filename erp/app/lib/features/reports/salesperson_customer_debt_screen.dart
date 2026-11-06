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
  String _filter = 'all';

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
      filter: _filter,
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
                  filter: _filter,
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
          const SizedBox(width: 10),
          AppSelectField<String>(
            label: s.showLabel,
            value: _filter,
            prefixIcon: Icons.filter_alt_outlined,
            options: <SelectOption<String>>[
              SelectOption<String>('all', s.allCustomers),
              SelectOption<String>('debtors', s.customersWithDebt),
              SelectOption<String>('creditors', s.customersWithCredit),
            ],
            onChanged: (value) {
              setState(() => _filter = value ?? 'all');
              _reload();
            },
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
    final headerStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
      fontSize: 14,
    );
    final dataStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width - 48,
        ),
        child: DataTable(
          border: TableBorder.all(
            color: theme.colorScheme.outline,
            width: 0.8,
          ),
          showCheckboxColumn: false,
          headingRowColor: WidgetStatePropertyAll<Color>(
            theme.colorScheme.surfaceContainerHighest,
          ),
          headingTextStyle: headerStyle,
          dataTextStyle: dataStyle,
          horizontalMargin: 12,
          columnSpacing: 22,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 48,
          columns: <DataColumn>[
            DataColumn(label: Center(child: Text('#', style: headerStyle))),
            DataColumn(
              label: Center(child: Text(s.customer, style: headerStyle)),
            ),
            DataColumn(
              label: Center(
                child: Text(s.previousBalance, style: headerStyle),
              ),
              numeric: true,
            ),
            DataColumn(
              label: Center(child: Text(s.debit, style: headerStyle)),
              numeric: true,
            ),
            DataColumn(
              label: Center(child: Text(s.credit, style: headerStyle)),
              numeric: true,
            ),
            DataColumn(
              label: Center(child: Text(s.balance, style: headerStyle)),
              numeric: true,
            ),
          ],
          rows: <DataRow>[
            for (var index = 0; index < rows.length; index++)
              DataRow(
                cells: <DataCell>[
                  DataCell(Center(child: Text('${index + 1}'))),
                  DataCell(
                    Center(
                      child: Text(
                        asString(rows[index]['customer']),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  DataCell(
                    Center(
                      child: MoneyText(asDouble(rows[index]['previous'])),
                    ),
                  ),
                  DataCell(
                    Center(child: MoneyText(asDouble(rows[index]['debit']))),
                  ),
                  DataCell(Center(child: _creditCell(rows[index]['credit']))),
                  DataCell(
                    Center(
                      child: MoneyText(
                        asDouble(rows[index]['balance']),
                        colorNegative: true,
                      ),
                    ),
                  ),
                ],
              ),
            DataRow(
              color: WidgetStatePropertyAll<Color>(
                theme.colorScheme.surfaceContainerHighest,
              ),
              cells: <DataCell>[
                const DataCell(Center(child: Text(''))),
                DataCell(
                  Center(
                    child: Text(
                      s.total,
                      style: headerStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                DataCell(
                  Center(child: MoneyText(asDouble(totals['previous']))),
                ),
                DataCell(Center(child: MoneyText(asDouble(totals['debit'])))),
                DataCell(Center(child: _creditCell(totals['credit']))),
                DataCell(
                  Center(
                    child: MoneyText(
                      asDouble(totals['balance']),
                      colorNegative: true,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The credit column stays blank when nothing was collected in the period.
  Widget _creditCell(dynamic value) {
    final amount = asDouble(value);
    if (amount == 0) return const Text('');
    return MoneyText(amount);
  }
}
