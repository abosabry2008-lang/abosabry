import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import '../customers/customer_statement_screen.dart';
import '../suppliers/supplier_statement_screen.dart';

/// Whether the statement hub is searching customers or suppliers.
enum StatementKind { customer, supplier }

/// Pick a customer or supplier and a date range, then open its statement.
class StatementHubScreen extends StatefulWidget {
  const StatementHubScreen({super.key, this.startWith});

  /// When provided, the matching list is shown immediately.
  final StatementKind? startWith;

  @override
  State<StatementHubScreen> createState() => _StatementHubScreenState();
}

class _StatementHubScreenState extends State<StatementHubScreen> {
  StatementKind? _kind;
  List<Map<String, dynamic>> _results = <Map<String, dynamic>>[];
  bool _loading = false;
  String? _error;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _kind = widget.startWith;
    if (_kind != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(''));
    }
  }

  String get _path =>
      _kind == StatementKind.supplier ? '/suppliers' : '/customers';

  String get _searchHint {
    final s = context.s;
    return _kind == StatementKind.supplier
        ? s.searchSuppliersHint
        : s.searchCustomersHint;
  }

  Future<void> _search(String query) async {
    if (_kind == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await context.read<Session>().api.get(
        _path,
        query: <String, dynamic>{'search': query, 'pageSize': 100},
      );
      if (!mounted) return;
      setState(() => _results = asMapList(asMap(json)['data']));
    } on ApiException catch (exception) {
      if (!mounted) return;
      setState(() => _error = exception.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = context.s.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectKind(StatementKind kind) {
    setState(() {
      _kind = kind;
      _results = <Map<String, dynamic>>[];
    });
    _search('');
  }

  void _open(Map<String, dynamic> row) {
    final s = context.s;
    final id = asString(row['id']);
    final name = asString(
      row['name'],
      fallback: _kind == StatementKind.supplier ? s.supplier : s.customer,
    );
    if (id.isEmpty) return;
    if (_kind == StatementKind.supplier) {
      openSupplierStatement(
        context,
        supplierId: id,
        supplierName: name,
        from: _from,
        to: _to,
      );
    } else {
      openCustomerStatement(
        context,
        customerId: id,
        customerName: name,
        from: _from,
        to: _to,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _selectKind(StatementKind.customer),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(s.customerStatement),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _selectKind(StatementKind.supplier),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: Text(s.supplierStatement),
                    ),
                  ),
                ],
              ),
              if (_kind != null) ...<Widget>[
                const SizedBox(height: 8),
                AppSearchField(
                  hintText: _searchHint,
                  onChanged: _search,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DateRangeButton(
                    from: _from,
                    to: _to,
                    onChanged: (from, to) => setState(() {
                      _from = from;
                      _to = to;
                    }),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final s = context.s;
    if (_kind == null) {
      return EmptyState(
        icon: Icons.description_outlined,
        title: s.statements,
        message: s.statementsHint,
      );
    }
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _results.isEmpty) {
      return ErrorView(message: _error!, onRetry: () => _search(''));
    }
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_outlined,
        title: _kind == StatementKind.supplier ? s.noSuppliers : s.noCustomers,
        message: s.noDataForFilters,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = _results[index];
        final name = asString(
          row['name'],
          fallback: _kind == StatementKind.supplier ? s.supplier : s.customer,
        );
        final phone = asStringOrNull(row['phone']);
        return SectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            title: Text(name),
            subtitle: phone == null ? null : Text(phone),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(row),
          ),
        );
      },
    );
  }
}
