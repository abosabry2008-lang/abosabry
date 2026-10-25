import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
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

/// Shared date-range + salesperson filter used by every sales-people report.
class _SalespersonFilter extends StatelessWidget {
  const _SalespersonFilter({
    required this.from,
    required this.to,
    required this.salespersonId,
    required this.onChanged,
    this.onPrint,
  });

  final DateTime? from;
  final DateTime? to;
  final String? salespersonId;
  final void Function(DateTime? from, DateTime? to, String? salespersonId) onChanged;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final salespeople = context.watch<SalespeopleController>().salespeople;
    return ReportHeader(
      onPrint: onPrint,
      filters: <Widget>[
        DateRangeButton(
          from: from,
          to: to,
          onChanged: (from, to) => onChanged(from, to, salespersonId),
        ),
        const SizedBox(height: 10),
        if (!context.watch<Session>().isSalesperson) AppSelectField<String?>(
          label: s.salesperson,
          value: salespersonId,
          prefixIcon: Icons.support_agent_outlined,
          options: <SelectOption<String?>>[
            SelectOption<String?>(null, s.allSalespeople),
            for (final person in salespeople)
              SelectOption<String?>(person.id, person.name),
          ],
          onChanged: (value) => onChanged(from, to, value),
        ),
      ],
    );
  }
}

/// Mixin-free base for the sales-people report screens: owns the filters and
/// reloads the controller when they change.
abstract class _SalespersonReportState<T extends StatefulWidget>
    extends State<T> {
  DateTime? from;
  DateTime? to;
  String? salespersonId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalespeopleController>().ensureLoaded();
    });
  }

  void applyFilters(DateTime? nextFrom, DateTime? nextTo, String? nextId) {
    setState(() {
      from = nextFrom;
      to = nextTo;
      salespersonId = nextId;
    });
    reload();
  }

  Future<void> reload();
}

// ---------------------------------------------------------------------------
// Consolidated sales note (إذن مجمع للمبيعات لكل مندوب)
// ---------------------------------------------------------------------------

class ConsolidatedSalesNoteScreen extends StatefulWidget {
  const ConsolidatedSalesNoteScreen({super.key});

  @override
  State<ConsolidatedSalesNoteScreen> createState() =>
      _ConsolidatedSalesNoteScreenState();
}

class _ConsolidatedSalesNoteScreenState
    extends _SalespersonReportState<ConsolidatedSalesNoteScreen> {
  @override
  Future<void> reload() => context
      .read<ReportsController>()
      .loadConsolidatedSalesNote(from: from, to: to, salespersonId: salespersonId);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final totals = asMap(controller.consolidatedSalesNote['totals']);
    final rows = asMapList(controller.consolidatedSalesNote['rows']);
    return ReportAsyncSection(
      loading: controller.loadingConsolidatedSalesNote,
      error: controller.consolidatedSalesNoteError,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: reload,
      header: _SalespersonFilter(
        from: from,
        to: to,
        salespersonId: salespersonId,
        onChanged: applyFilters,
        onPrint: () => PrintService.printConsolidatedSalesNote(
          context,
          from: from,
          to: to,
          salespersonId: salespersonId,
        ),
      ),
      children: <Widget>[
        ReportTotalsCard(
          title: s.totals,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.salespeople,
              value: Formatters.integer(asDouble(totals['salespeople'])),
            ),
            ReportKeyValueRow(
              label: s.orders,
              value: Formatters.integer(asDouble(totals['orders'])),
            ),
            ReportKeyValueRow(
              label: s.quantity,
              value: Formatters.integer(asDouble(totals['quantity'])),
            ),
            ReportKeyValueRow(
              label: s.netSales,
              amount: asDouble(totals['net']),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final row in rows) ...<Widget>[
          _SalespersonSection(
            title: asString(row['salesperson'], fallback: s.unassigned),
            subtitle: '${s.orders}: ${Formatters.integer(asDouble(row['orders']))} · '
                '${s.quantity}: ${Formatters.integer(asDouble(row['quantity']))} · '
                '${s.netSales}: ${Formatters.money(asDouble(row['net']))}',
            lines: asMapList(row['lines']),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// One salesperson's consolidated lines.
class _SalespersonSection extends StatelessWidget {
  const _SalespersonSection({
    required this.title,
    required this.subtitle,
    required this.lines,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> lines;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SectionCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: <Widget>[
          for (final line in lines)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                asString(line['name'], fallback: asString(line['sku'])),
              ),
              subtitle: Text(
                '${asStringOrNull(line['category']) == null ? '' : '${s.category}: ${asString(line['category'])} · '}'
                '${asString(line['sku'])} · ${s.quantity}: '
                '${Formatters.integer(asDouble(line['quantity']))} '
                '${asString(line['unit'])}',
              ),
              trailing: MoneyText(asDouble(line['net'])),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profitability per salesperson (ربحية كل مندوب)
// ---------------------------------------------------------------------------

class ProfitBySalespersonScreen extends StatefulWidget {
  const ProfitBySalespersonScreen({super.key});

  @override
  State<ProfitBySalespersonScreen> createState() =>
      _ProfitBySalespersonScreenState();
}

class _ProfitBySalespersonScreenState
    extends _SalespersonReportState<ProfitBySalespersonScreen> {
  @override
  Future<void> reload() => context
      .read<ReportsController>()
      .loadProfitBySalesperson(from: from, to: to, salespersonId: salespersonId);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final totals = asMap(controller.profitBySalesperson['totals']);
    final rows = asMapList(controller.profitBySalesperson['rows']);
    return ReportAsyncSection(
      loading: controller.loadingProfitBySalesperson,
      error: controller.profitBySalespersonError,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: reload,
      header: _SalespersonFilter(
        from: from,
        to: to,
        salespersonId: salespersonId,
        onChanged: applyFilters,
        onPrint: () => PrintService.printProfitBySalesperson(
          context,
          from: from,
          to: to,
          salespersonId: salespersonId,
        ),
      ),
      children: <Widget>[
        ReportTotalsCard(
          title: s.totals,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.revenue,
              amount: asDouble(totals['revenue']),
            ),
            ReportKeyValueRow(
              label: s.costOfSales,
              amount: asDouble(totals['cost']),
            ),
            ReportKeyValueRow(
              label: s.netProfit,
              value: '${Formatters.money(asDouble(totals['profit']))} '
                  '(${Formatters.money(asDouble(totals['margin']))}%)',
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.profitBySalesperson,
          subtitle: s.profitBySalespersonHint,
          child: Column(
            children: <Widget>[
              for (final row in rows) _SalespersonProfitTile(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _SalespersonProfitTile extends StatelessWidget {
  const _SalespersonProfitTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final profit = asDouble(row['profit']);
    final revenue = asDouble(row['revenue']);
    final margin = asDouble(row['margin']);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(asString(row['salesperson'], fallback: s.unassigned)),
      subtitle: Text(
        '${s.orders}: ${Formatters.integer(asDouble(row['orders']))} · '
        '${s.revenue}: ${Formatters.money(revenue)} · '
        '${s.costOfSales}: ${Formatters.money(asDouble(row['cost']))} · '
        '${Formatters.money(margin)}%',
      ),
      trailing: MoneyText(profit, colorNegative: true),
    );
  }
}

// ---------------------------------------------------------------------------
// Collections per salesperson (تحصيلات كل مندوب)
// ---------------------------------------------------------------------------

class CollectionsBySalespersonScreen extends StatefulWidget {
  const CollectionsBySalespersonScreen({super.key});

  @override
  State<CollectionsBySalespersonScreen> createState() =>
      _CollectionsBySalespersonScreenState();
}

class _CollectionsBySalespersonScreenState
    extends _SalespersonReportState<CollectionsBySalespersonScreen> {
  @override
  Future<void> reload() => context.read<ReportsController>()
      .loadCollectionsBySalesperson(
        from: from,
        to: to,
        salespersonId: salespersonId,
      );

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final totals = asMap(controller.collectionsBySalesperson['totals']);
    final rows = asMapList(controller.collectionsBySalesperson['rows']);
    return ReportAsyncSection(
      loading: controller.loadingCollectionsBySalesperson,
      error: controller.collectionsBySalespersonError,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: reload,
      header: _SalespersonFilter(
        from: from,
        to: to,
        salespersonId: salespersonId,
        onChanged: applyFilters,
        onPrint: () => PrintService.printCollectionsBySalesperson(
          context,
          from: from,
          to: to,
          salespersonId: salespersonId,
        ),
      ),
      children: <Widget>[
        ReportTotalsCard(
          title: s.totals,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.salespeople,
              value: Formatters.integer(asDouble(totals['salespeople'])),
            ),
            ReportKeyValueRow(
              label: s.collectionVouchers,
              value: Formatters.integer(asDouble(totals['vouchers'])),
            ),
            ReportKeyValueRow(
              label: s.collected,
              amount: asDouble(totals['amount']),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.collectionsBySalesperson,
          subtitle: s.collectionsBySalespersonHint,
          child: Column(
            children: <Widget>[
              for (final row in rows) _SalespersonCollectionTile(row: row),
            ],
          ),
        ),
      ],
    );
  }
}

class _SalespersonCollectionTile extends StatelessWidget {
  const _SalespersonCollectionTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final customers = asMapList(row['customers'])
        .map((entry) => '${asString(entry['customer'], fallback: s.customer)} '
            '(${Formatters.money(asDouble(entry['amount']))})')
        .join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      isThreeLine: customers.isNotEmpty,
      title: Text(asString(row['salesperson'], fallback: s.unassigned)),
      subtitle: Text(
        '${s.collectionVouchers}: ${Formatters.integer(asDouble(row['vouchers']))}'
        '${customers.isEmpty ? '' : '\n$customers'}',
      ),
      trailing: MoneyText(asDouble(row['amount'])),
    );
  }
}

// ---------------------------------------------------------------------------
// Detailed salesperson statement (كشف حساب مندوب)
// ---------------------------------------------------------------------------

class SalespersonStatementScreen extends StatefulWidget {
  const SalespersonStatementScreen({super.key, this.initialSalespersonId});

  final String? initialSalespersonId;

  @override
  State<SalespersonStatementScreen> createState() =>
      _SalespersonStatementScreenState();
}

class _SalespersonStatementScreenState
    extends _SalespersonReportState<SalespersonStatementScreen> {
  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    salespersonId = widget.initialSalespersonId ??
        (session.isSalesperson ? session.user?.id : null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalespeopleController>().ensureLoaded();
      if (salespersonId != null) reload();
    });
  }

  @override
  Future<void> reload() async {
    final id = salespersonId;
    final controller = context.read<ReportsController>();
    if (id == null || id.isEmpty) return;
    await controller.loadSalespersonStatement(
      salespersonId: id,
      from: from,
      to: to,
    );
  }

  // Changing the salesperson must load immediately; changing only the dates
  // keeps the current selection.
  @override
  void applyFilters(DateTime? nextFrom, DateTime? nextTo, String? nextId) {
    setState(() {
      from = nextFrom;
      to = nextTo;
      salespersonId = nextId;
    });
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReportsController>();
    final data = controller.salespersonStatement;
    final person = asMap(data['salesperson']);
    final totals = asMap(data['totals']);
    final rows = asMapList(data['rows']);
    final byProduct = asMapList(data['byProduct']);
    final selectedId = salespersonId;

    return ReportAsyncSection(
      loading: controller.loadingSalespersonStatement,
      error: controller.salespersonStatementError,
      isEmpty: selectedId == null || (rows.isEmpty && byProduct.isEmpty),
      emptyTitle: selectedId == null
          ? s.pickSalespersonFirst
          : s.noDataForFilters,
      onRetry: reload,
      header: _SalespersonFilter(
        from: from,
        to: to,
        salespersonId: salespersonId,
        onChanged: applyFilters,
        onPrint: selectedId == null
            ? null
            : () => PrintService.printSalespersonStatement(
                  context,
                  selectedId,
                  from: from,
                  to: to,
                ),
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
        ReportTotalsCard(
          title: s.totals,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.openingBalance,
              amount: asDouble(data['openingBalance']),
            ),
            ReportKeyValueRow(
              label: s.sales,
              amount: asDouble(totals['sales']),
            ),
            ReportKeyValueRow(
              label: s.collected,
              amount: asDouble(totals['collections']),
            ),
            ReportKeyValueRow(
              label: s.closingBalance,
              amount: asDouble(totals['closingBalance']),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.accountStatement,
          subtitle: s.lineCount(rows.length),
          child: Column(
            children: <Widget>[
              for (final row in rows) _StatementLineTile(row: row),
            ],
          ),
        ),
        if (byProduct.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          SectionCard(
            title: s.soldProducts,
            child: Column(
              children: <Widget>[
                for (final line in byProduct)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      asString(line['name'], fallback: asString(line['sku'])),
                    ),
                    subtitle: Text(
                      '${asString(line['sku'])} · ${s.quantity}: '
                      '${Formatters.integer(asDouble(line['quantity']))}',
                    ),
                    trailing: MoneyText(asDouble(line['net'])),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatementLineTile extends StatelessWidget {
  const _StatementLineTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final isSale = asString(row['type']) == 'SALE';
    final customer = asStringOrNull(row['customer']);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isSale ? Icons.arrow_upward : Icons.arrow_downward,
        size: 18,
      ),
      title: Text('${asString(row['reference'])} · ${asString(row['date'])}'),
      subtitle: Text(
        <String>[
          isSale ? s.sales : s.collected,
          if (customer != null && customer.isNotEmpty) customer,
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          MoneyText(isSale ? asDouble(row['debit']) : asDouble(row['credit'])),
          Text(
            Formatters.money(asDouble(row['balance'])),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
