import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../models/account_statement.dart';
import '../../widgets/error_view.dart';
import '../../widgets/statement_view.dart';
import '../shell/navigation.dart';

/// Account statement for a single supplier.
class SupplierStatementScreen extends StatefulWidget {
  const SupplierStatementScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
    this.from,
    this.to,
  });

  final String supplierId;
  final String supplierName;
  final DateTime? from;
  final DateTime? to;

  @override
  State<SupplierStatementScreen> createState() =>
      _SupplierStatementScreenState();
}

/// Navigates to the supplier statement with a Print action in the app bar.
Future<bool?> openSupplierStatement(
  BuildContext context, {
  required String supplierId,
  required String supplierName,
  DateTime? from,
  DateTime? to,
}) =>
    pushScreen<bool>(
      context,
      context.s.statement,
      SupplierStatementScreen(
        supplierId: supplierId,
        supplierName: supplierName,
        from: from,
        to: to,
      ),
      actions: <Widget>[
        IconButton(
          tooltip: context.s.print,
          icon: const Icon(Icons.print_outlined),
          onPressed: () => PrintService.printSupplierStatement(
            context,
            supplierId,
            from: from,
            to: to,
          ),
        ),
      ],
    );

class _SupplierStatementScreenState extends State<SupplierStatementScreen> {
  AccountStatement? _statement;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    setState(() {
      _loading = _statement == null;
      _error = null;
    });
    try {
      final data = await api.getObject(
        '/reports/suppliers/${widget.supplierId}/statement',
        query: <String, dynamic>{
          if (widget.from != null) 'from': Formatters.isoDate(widget.from!),
          if (widget.to != null) 'to': Formatters.isoDate(widget.to!),
        },
      );
      if (!mounted) return;
      setState(() => _statement = AccountStatement.fromJson(data));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = context.s.couldNotLoadStatement);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final statement = _statement;
    if (_loading && statement == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (statement == null) {
      return Scaffold(
        body: ErrorView(
          message: _error ?? s.statementNotFound,
          onRetry: _load,
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            StatementView(statement: statement),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => PrintService.printSupplierStatement(
                context,
                widget.supplierId,
                from: statement.from,
                to: statement.to,
              ),
              icon: const Icon(Icons.print_outlined),
              label: Text(s.printStatement),
            ),
          ],
        ),
      ),
    );
  }
}
