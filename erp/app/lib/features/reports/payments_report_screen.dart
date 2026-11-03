import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Detail of every customer receipt and supplier payment with filters for the
/// period, direction, method and cash box.
class PaymentsReportScreen extends StatefulWidget {
  const PaymentsReportScreen({super.key});

  @override
  State<PaymentsReportScreen> createState() => _PaymentsReportScreenState();
}

class _PaymentsReportScreenState extends State<PaymentsReportScreen> {
  DateTime? _from;
  DateTime? _to;
  String _direction = '';
  String _method = '';
  String? _boxId;
  String _search = '';
  List<Map<String, dynamic>> _boxes = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};

  static const List<String> _methods = <String>[
    'CASH',
    'CARD',
    'BANK_TRANSFER',
    'MOBILE_MONEY',
    'CHEQUE',
    'OTHER',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoxes());
  }

  Future<void> _loadBoxes() async {
    try {
      final rows = await context.read<Session>().api.getList('/treasury/boxes');
      if (!mounted) return;
      setState(() => _boxes = rows.map(asMap).toList());
    } catch (_) {
      // The report still works without the box filter.
    }
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.getObject(
            '/reports/payments',
            query: <String, dynamic>{
              if (_from != null) 'from': _from!.toUtc().toIso8601String(),
              if (_to != null) 'to': Formatters.isoRangeEnd(_to!),
              if (_direction.isNotEmpty) 'direction': _direction,
              if (_method.isNotEmpty) 'method': _method,
              if (_boxId != null) 'cashBoxId': _boxId,
              if (_search.trim().isNotEmpty) 'search': _search.trim(),
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
    final theme = Theme.of(context);
    final rows = asMapList(_data['rows']);
    final totals = asMap(_data['totals']);

    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: rows.isEmpty,
      emptyTitle: s.noPayments,
      emptyIcon: Icons.payments_outlined,
      onRetry: _load,
      header: ReportHeader(
        filters: <Widget>[
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
          AppSelectField<String>(
            label: s.direction,
            value: _direction,
            hint: s.allPayments,
            options: <SelectOption<String>>[
              SelectOption<String>('', s.allPayments),
              SelectOption<String>('INBOUND', s.inboundReceived),
              SelectOption<String>('OUTBOUND', s.outboundPaid),
            ],
            onChanged: (value) {
              setState(() => _direction = value ?? '');
              _load();
            },
          ),
          AppSelectField<String>(
            label: s.paymentMethod,
            value: _method,
            hint: s.paymentMethod,
            options: <SelectOption<String>>[
              SelectOption<String>('', s.paymentMethod),
              ..._methods.map(
                (method) => SelectOption<String>(method, s.status(method)),
              ),
            ],
            onChanged: (value) {
              setState(() => _method = value ?? '');
              _load();
            },
          ),
          AppSelectField<String>(
            label: s.cashBox,
            value: _boxId ?? '',
            hint: s.allBoxes,
            options: <SelectOption<String>>[
              SelectOption<String>('', s.allBoxes),
              ..._boxes.map(
                (box) => SelectOption<String>(
                  asString(box['id']),
                  asString(box['name']),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => _boxId = (value == null || value.isEmpty) ? null : value);
              _load();
            },
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: AppSearchField(
                  hintText: s.searchPaymentsHint,
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
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.paymentsReport,
          subtitle: s.paymentsReportHint,
          child: Text(s.paymentsReportExplainer, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 12),
        ReportTotalsCard(
          title: s.paymentsReport,
          subtitle: s.paymentsReportHint,
          rows: <Widget>[
            ReportKeyValueRow(
              label: s.countLabel,
              value: Formatters.integer(asInt(totals['count'])),
            ),
            ReportKeyValueRow(
              label: s.inboundReceived,
              amount: asDouble(totals['inTotal']),
            ),
            ReportKeyValueRow(
              label: s.outboundPaid,
              amount: asDouble(totals['outTotal']),
            ),
            ReportKeyValueRow(
              label: s.netMovement,
              amount: asDouble(totals['net']),
              emphasise: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: s.payments,
          subtitle: s.paymentsReportHint,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 16,
              columns: <DataColumn>[
                DataColumn(label: Text(s.date)),
                DataColumn(label: Text(s.numberLabel)),
                DataColumn(label: Text(s.direction)),
                DataColumn(label: Text(s.party)),
                DataColumn(label: Text(s.paymentMethod)),
                DataColumn(label: Text(s.invoice)),
                DataColumn(label: Text(s.cashBox)),
                DataColumn(label: Text(s.amount), numeric: true),
                DataColumn(label: Text(s.reference)),
                DataColumn(label: Text(s.notes)),
              ],
              rows: <DataRow>[
                for (final row in rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(Text(Formatters.date(asDate(row['paidAt'])))),
                      DataCell(Text(asString(row['number']))),
                      DataCell(Text(s.status(asString(row['direction'])))),
                      DataCell(
                        SizedBox(
                          width: 200,
                          child: Text(
                            _partyName(row, s.walkInCustomer),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(s.status(asString(row['method'])))),
                      DataCell(
                        Text(
                          asString(asMap(row['invoice'])['number'], fallback: '—'),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Text(
                            asString(asMap(row['cashBox'])['name'], fallback: '—'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        MoneyText(
                          asDouble(row['amount']),
                          colorNegative: true,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: Text(
                            asString(row['reference'], fallback: '—'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(
                            asString(row['note'], fallback: '—'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
    );
  }

  String _partyName(Map<String, dynamic> row, String walkIn) {
    final direction = asString(row['direction']);
    if (direction == 'OUTBOUND') {
      return asString(asMap(row['supplier'])['name'], fallback: '—');
    }
    return asString(asMap(row['customer'])['name'], fallback: walkIn);
  }
}
