import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Inventory + cash + customer debt − supplier balances, with drill-down lists.
class InvestmentEquationScreen extends StatefulWidget {
  const InvestmentEquationScreen({super.key});

  @override
  State<InvestmentEquationScreen> createState() =>
      _InvestmentEquationScreenState();
}

class _InvestmentEquationScreenState extends State<InvestmentEquationScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context
          .read<Session>()
          .api
          .getObject('/reports/investment-equation');
      if (!mounted) return;
      setState(() => _data = data);
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
    final inventory = asMap(_data['inventory']);
    final cash = asMap(_data['cash']);
    final customers = asMap(_data['customers']);
    final suppliers = asMap(_data['suppliers']);
    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: _data.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: _load,
      header: ReportHeader(
        onPrint: () => PrintService.printInvestmentEquation(context),
      ),
      children: <Widget>[
        SectionCard(
          title: s.investmentEquation,
          child: Column(
            children: <Widget>[
              _Line(
                label: s.inventory,
                amount: asDouble(inventory['total']),
                details: asMapList(inventory['rows']),
                detailLabel: (row) =>
                    '${asString(row['sku'])} ${asString(row['name'])} · ${Formatters.integer(asDouble(row['quantity']))}',
              ),
              _Line(
                label: s.cashBoxes,
                amount: asDouble(cash['total']),
                details: asMapList(cash['rows']),
                detailLabel: (row) => asString(row['name']),
              ),
              _Line(
                label: s.customerDebt,
                amount: asDouble(customers['total']),
                details: asMapList(customers['rows']),
                detailLabel: (row) => asString(row['name']),
              ),
              _Line(
                label: s.supplierBalances,
                amount: -asDouble(suppliers['total']),
                details: asMapList(suppliers['rows']),
                detailLabel: (row) => asString(row['name']),
              ),
              const Divider(),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      s.netInvestment,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  MoneyText(
                    asDouble(_data['net']),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.amount,
    required this.details,
    required this.detailLabel,
  });

  final String label;
  final double amount;
  final List<Map<String, dynamic>> details;
  final String Function(Map<String, dynamic>) detailLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          MoneyText(amount),
        ],
      ),
      children: <Widget>[
        for (final row in details)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    detailLabel(row),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                MoneyText(
                  asDouble(row['value'] ?? row['balance']),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
