import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/account.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// General ledger for one account: opening balance, every journal line in the
/// period and a running balance.
class GeneralLedgerScreen extends StatefulWidget {
  const GeneralLedgerScreen({
    super.key,
    this.initialAccountId,
    this.initialFrom,
    this.initialTo,
  });

  final String? initialAccountId;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  State<GeneralLedgerScreen> createState() => _GeneralLedgerScreenState();
}

class _GeneralLedgerScreenState extends State<GeneralLedgerScreen> {
  List<Account> _accounts = <Account>[];
  String? _accountId;
  DateTime? _from;
  DateTime? _to;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _accountId = widget.initialAccountId;
    _from = widget.initialFrom;
    _to = widget.initialTo;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccounts());
  }

  Future<void> _loadAccounts() async {
    try {
      final rows = await context.read<Session>().api.getList('/accounting/accounts');
      if (!mounted) return;
      setState(() {
        _accounts = rows.map(Account.fromJson).toList();
        _accountId ??= _accounts.isEmpty ? null : _accounts.first.id;
      });
      if (_accountId != null) await _load();
      if (mounted) setState(() => _loading = false);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    final accountId = _accountId;
    if (accountId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.getObject(
            '/reports/general-ledger',
            query: <String, dynamic>{
              'accountId': accountId,
              if (_from != null) 'from': _from!.toUtc().toIso8601String(),
              if (_to != null) 'to': Formatters.isoRangeEnd(_to!),
            },
          );
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
    final rows = asMapList(_data['rows']);
    final totals = asMap(_data['totals']);
    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: _accountId == null,
      emptyTitle: s.chooseAccount,
      emptyIcon: Icons.menu_book_outlined,
      onRetry: _load,
      header: ReportHeader(
        filters: <Widget>[
          AppSelectField<String?>(
            label: s.accountWord,
            value: _accountId,
            hint: s.chooseAccount,
            prefixIcon: Icons.account_tree_outlined,
            options: _accounts
                .map(
                  (account) => SelectOption<String?>(
                    account.id,
                    '${account.code} · ${account.name}',
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null || value.isEmpty) return;
              setState(() => _accountId = value);
              _load();
            },
          ),
          DateRangeButton(
            from: _from,
            to: _to,
            onChanged: (from, to) {
              setState(() {
                _from = from;
                _to = to;
              });
              _load();
            },
          ),
          FilledButton.tonalIcon(
            onPressed: _load,
            icon: const Icon(Icons.filter_alt_outlined),
            label: Text(s.applyFilters),
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.generalLedger,
          subtitle: asString(asMap(_data['account'])['name']),
          child: Column(
            children: <Widget>[
              ReportKeyValueRow(
                label: s.openingShort,
                amount: asDouble(_data['opening']),
              ),
              const Divider(),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(s.noDataForFilters),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 18,
                    columns: <DataColumn>[
                      DataColumn(label: Text(s.date)),
                      DataColumn(label: Text(s.numberLabel)),
                      DataColumn(label: Text(s.description)),
                      DataColumn(label: Text(s.debit), numeric: true),
                      DataColumn(label: Text(s.credit), numeric: true),
                      DataColumn(label: Text(s.balance), numeric: true),
                    ],
                    rows: rows
                        .map(
                          (row) => DataRow(
                            cells: <DataCell>[
                              DataCell(Text(Formatters.date(asDate(row['date'])))),
                              DataCell(Text(asString(row['entryNumber']))),
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Text(
                                    asString(
                                      row['description'],
                                      fallback: asString(row['memo']),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(MoneyText(asDouble(row['debit']))),
                              DataCell(MoneyText(asDouble(row['credit']))),
                              DataCell(MoneyText(asDouble(row['balance']))),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              const Divider(),
              ReportKeyValueRow(
                label: s.total,
                amount: asDouble(totals['debit']) - asDouble(totals['credit']),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
