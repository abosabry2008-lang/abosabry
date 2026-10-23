import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../models/invoice.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_view.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../payments/payment_form_screen.dart';
import '../shell/navigation.dart';
import 'invoice_edit_screen.dart';

/// Read-only invoice with issue / void actions and payment recording.
class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({
    super.key,
    required this.invoiceId,
    this.initial,
  });

  final String invoiceId;
  final Invoice? initial;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Invoice? _invoice;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  bool _showProfit = false;

  @override
  void initState() {
    super.initState();
    _invoice = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    setState(() {
      _loading = _invoice == null;
      _error = null;
    });
    try {
      final data = await api.getObject('/invoices/${widget.invoiceId}');
      if (!mounted) return;
      setState(() => _invoice = Invoice.fromJson(data));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordPayment() async {
    final invoice = _invoice;
    if (invoice == null) return;
    final created = await pushScreen<bool>(
      context,
      context.s.recordPayment,
      PaymentFormScreen(
        direction: 'INBOUND',
        invoiceId: invoice.id,
        invoiceLabel: invoice.number,
        customerId: invoice.customerId,
        customerName: invoice.customerName,
        initialAmount: invoice.balance > 0 ? invoice.balance : invoice.total,
        lockTarget: true,
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _print() => PrintService.printInvoice(context, widget.invoiceId);

  Future<void> _edit() async {
    final invoice = _invoice;
    if (invoice == null) return;
    final updated = await pushScreen<bool>(
      context,
      '${context.s.edit} ${invoice.number}',
      InvoiceEditScreen(invoice: invoice),
    );
    if (updated == true) await _load();
  }

  Future<void> _issue() async {
    final s = context.s;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await api.post(
        '/invoices/${widget.invoiceId}/issue',
        body: const <String, dynamic>{},
      );
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(s.invoiceIssued)));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _void() async {
    final s = context.s;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await confirmDialog(
      context,
      title: s.voidInvoiceQ,
      message: s.voidInvoiceMessage,
      confirmLabel: s.continueLabel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await api.post(
        '/invoices/${widget.invoiceId}/void',
        body: const <String, dynamic>{},
      );
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(s.invoiceVoided)));
      navigator.pop(true);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = context.watch<Session>();
    final invoice = _invoice;
    if (_loading && invoice == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (invoice == null) {
      return Scaffold(
        body: ErrorView(
          message: _error ?? s.invoiceNotFound,
          onRetry: _load,
        ),
      );
    }

    final canManage = session.can('invoices');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: invoice.number,
              subtitle: invoice.customerName ?? s.walkInCustomer,
              trailing: StatusChip(
                status: invoice.isOverdue ? 'OVERDUE' : invoice.status,
                label: invoice.isOverdue ? s.overdue : s.status(invoice.status),
              ),
              child: Column(
                children: <Widget>[
                  if (invoice.salesOrderNumber != null && invoice.salesOrderNumber!.isNotEmpty)
                    _InfoRow(
                      label: s.salesOrder,
                      value: invoice.salesOrderNumber ?? '-',
                    ),
                  _InfoRow(
                    label: s.issued,
                    value: Formatters.date(invoice.issueDate),
                  ),
                  _InfoRow(
                    label: s.due,
                    value: Formatters.date(invoice.dueDate),
                  ),
                  if (invoice.notes != null && invoice.notes!.isNotEmpty)
                    _InfoRow(label: s.notes, value: invoice.notes!),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: s.lines,
              subtitle: s.lineCount(invoice.lines.length),
              trailing: session.canViewProfit
                  ? TextButton.icon(
                      onPressed: () => setState(() => _showProfit = !_showProfit),
                      icon: Icon(
                        _showProfit
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      label: Text(_showProfit ? s.hideProfit : s.showProfit),
                    )
                  : null,
              child: invoice.lines.isEmpty
                  ? Text(
                      s.noLinesOnInvoice,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    )
                  : Column(
                      children: <Widget>[
                        for (final line in invoice.lines)
                          _LineTile(
                            description: line.description,
                            quantity: line.quantity,
                            unitPrice: line.unitPrice,
                            total: line.total,
                            currencyCode: invoice.currencyCode,
                            profit: _showProfit && session.canViewProfit
                                ? line.profit
                                : null,
                          ),
                      ],
                    ),
            ),
            if (_showProfit && session.canViewProfit) ...<Widget>[
              const SizedBox(height: 16),
              SectionCard(
                title: s.netProfit,
                child: Column(
                  children: <Widget>[
                    _TotalRow(
                      label: s.netSales,
                      amount: invoice.lines.fold<double>(
                        0,
                        (sum, line) => sum + line.netRevenue,
                      ),
                      currencyCode: invoice.currencyCode,
                    ),
                    _TotalRow(
                      label: s.costOfSales,
                      amount: -invoice.lines.fold<double>(
                        0,
                        (sum, line) => sum + line.quantity * line.unitCost,
                      ),
                      currencyCode: invoice.currencyCode,
                    ),
                    const Divider(),
                    _TotalRow(
                      label: s.netProfit,
                      amount: invoice.lines.fold<double>(
                        0,
                        (sum, line) => sum + line.profit,
                      ),
                      currencyCode: invoice.currencyCode,
                      emphasise: true,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: s.totals,
              child: Column(
                children: <Widget>[
                  _TotalRow(
                    label: s.subtotal,
                    amount: invoice.subtotal,
                    currencyCode: invoice.currencyCode,
                  ),
                  _TotalRow(
                    label: s.discountWord,
                    amount: -invoice.discountTotal,
                    currencyCode: invoice.currencyCode,
                  ),
                  _TotalRow(
                    label: s.tax,
                    amount: invoice.taxTotal,
                    currencyCode: invoice.currencyCode,
                  ),
                  const Divider(),
                  _TotalRow(
                    label: s.total,
                    amount: invoice.total,
                    currencyCode: invoice.currencyCode,
                    emphasise: true,
                  ),
                  _TotalRow(
                    label: s.paid,
                    amount: -invoice.amountPaid,
                    currencyCode: invoice.currencyCode,
                  ),
                  _TotalRow(
                    label: s.balance,
                    amount: invoice.balance,
                    currencyCode: invoice.currencyCode,
                    emphasise: true,
                  ),
                  if (invoice.customerId != null) ...<Widget>[
                    const Divider(),
                    _TotalRow(
                      label: s.previousBalanceLabel,
                      amount: invoice.previousBalance,
                      currencyCode: invoice.currencyCode,
                    ),
                    _TotalRow(
                      label: s.totalDueLabel,
                      amount: invoice.previousBalance + invoice.balance,
                      currencyCode: invoice.currencyCode,
                      emphasise: true,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _print,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(s.print),
                ),
                if (session.isAdmin && invoice.status != 'VOID')
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _edit,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(s.edit),
                  ),
              ],
            ),
            if (invoice.status != 'VOID') ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  // Issuing is a single tap: no confirmation step. Any operator
                  // who may write invoices can issue; only an admin may edit or
                  // void an issued invoice.
                  if (invoice.canIssue && canManage)
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _issue,
                      icon: const Icon(Icons.send_outlined),
                      label: Text(s.issue),
                    ),
                  if (invoice.status == 'ISSUED' ||
                      invoice.status == 'PARTIALLY_PAID')
                    FilledButton.icon(
                      onPressed: _busy ? null : _recordPayment,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(s.recordPayment),
                    ),
                  if (invoice.canVoid && session.isAdmin)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _void,
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(s.voidLabel),
                    ),
                ],
              ),
            ],
            if (_busy) ...<Widget>[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.currencyCode,
    this.profit,
  });

  final String description;
  final int quantity;
  final double unitPrice;
  final double total;
  final String? currencyCode;
  /// Line profit; null hides it (non-managers, or the toggle is off).
  final double? profit;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(description.isEmpty ? s.itemFallback : description,
                    style: theme.textTheme.bodyLarge),
                Text(
                  s.qtyTimesPrice(
                    '$quantity',
                    Formatters.money(unitPrice, currencyCode: currencyCode),
                  ),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                if (profit != null)
                  Text(
                    '${s.netProfit}: ${Formatters.money(profit!, currencyCode: currencyCode)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: profit! < 0 ? theme.colorScheme.error : Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          MoneyText(
            total,
            currencyCode: currencyCode,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    this.currencyCode,
    this.emphasise = false,
  });

  final String label;
  final double amount;
  final String? currencyCode;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        emphasise ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          MoneyText(
            amount,
            currencyCode: currencyCode,
            style: style?.copyWith(
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
