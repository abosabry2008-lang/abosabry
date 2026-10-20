import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/sales_order.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_view.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../shell/navigation.dart';
import 'sales_order_form_screen.dart';

/// Read-only sales order with confirm / fulfil / cancel / invoice actions.
class SalesOrderDetailScreen extends StatefulWidget {
  const SalesOrderDetailScreen({
    super.key,
    required this.orderId,
    this.initial,
  });

  final String orderId;
  final SalesOrder? initial;

  @override
  State<SalesOrderDetailScreen> createState() => _SalesOrderDetailScreenState();
}

class _SalesOrderDetailScreenState extends State<SalesOrderDetailScreen> {
  SalesOrder? _order;
  bool _loading = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _order = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    setState(() {
      _loading = _order == null;
      _error = null;
    });
    try {
      final data = await api.getObject('/sales-orders/${widget.orderId}');
      if (!mounted) return;
      setState(() => _order = SalesOrder.fromJson(data));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(
    String action, {
    String? confirmTitle,
    String? confirmMessage,
    String? successMessage,
    bool closeOnSuccess = false,
  }) async {
    if (confirmTitle != null) {
      final confirmed = await confirmDialog(
        context,
        title: confirmTitle,
        message: confirmMessage,
        confirmLabel: context.s.continueLabel,
      );
      if (!confirmed) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await api.post(
        '/sales-orders/${widget.orderId}/$action',
        body: const <String, dynamic>{},
      );
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(successMessage ?? context.s.salesOrderUpdated)),
      );
      if (closeOnSuccess) navigator.pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fulfils the order, first warning the operator when items are not on hand.
  /// The warning offers to deliver only the available quantity (skipping the
  /// missing lines) so the rest can be purchased and delivered later.
  Future<void> _fulfill() async {
    final api = context.read<Session>().api;
    final s = context.s;
    setState(() => _busy = true);
    Map<String, dynamic>? availability;
    try {
      availability = await api.getObject(
        '/sales-orders/${widget.orderId}/availability',
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        setState(() => _busy = false);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final canFulfillEverything = availability['canFulfillEverything'] == true;
    if (canFulfillEverything) {
      await _act(
        'fulfill',
        confirmTitle: s.fulfilAllQ,
        confirmMessage: s.fulfilAllMessage,
        successMessage: s.salesOrderFulfilled,
      );
      return;
    }

    // Shortages found — show what is missing and offer to skip it.
    final lines = (availability['lines'] is List)
        ? (availability['lines'] as List).whereType<Map>().toList()
        : const <Map>[];
    final short = lines
        .where((line) => (line['shortfall'] as num? ?? 0) > 0)
        .toList();
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.shortageWarningTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(s.shortageWarningMessage),
            const SizedBox(height: 12),
            for (final line in short)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${line['productName']}: '
                  '${line['available']} / ${line['requested']}',
                ),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('partial'),
            child: Text(s.fulfilAvailableOnly),
          ),
        ],
      ),
    );
    if (choice != 'partial' || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post(
        '/sales-orders/${widget.orderId}/fulfill',
        body: <String, dynamic>{'onlyAvailable': true},
      );
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(s.fulfilOnlyAvailableDone)),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final order = _order;
    if (order == null) return;
    final saved = await pushScreen<bool>(
      context,
      context.s.editOrder,
      SalesOrderFormScreen(order: order),
    );
    if (saved ?? false) await _load();
  }

  Future<void> _createInvoice() async {
    if (!mounted) return;
    setState(() => _busy = true);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post(
        '/invoices',
        body: <String, dynamic>{'salesOrderId': widget.orderId},
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.s.draftInvoiceCreated)),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final order = _order;
    if (_loading && order == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (order == null) {
      return Scaffold(
        body: ErrorView(
          message: _error ?? s.salesOrderNotFound,
          onRetry: _load,
        ),
      );
    }

    final canManage = context.watch<Session>().can('sales');
    final canCancelOrder = context.watch<Session>().can('sales.cancel');
    final theme = Theme.of(context);
    final canConfirm = order.status == 'DRAFT';
    final canFulfill = order.status == 'CONFIRMED' ||
        order.status == 'PARTIALLY_FULFILLED';
    // Admins can cancel any order that is not already cancelled — including a
    // fulfilled one, whose stock and ledger entry are reversed by the API.
    final canCancel = canCancelOrder && order.status != 'CANCELLED';
    // Admins can also rewrite the lines of an order that already shipped.
    final canEdit = order.status != 'CANCELLED' &&
        (order.status == 'DRAFT' || canCancelOrder);
    final canInvoice = order.status == 'CONFIRMED' ||
        order.status == 'PARTIALLY_FULFILLED' ||
        order.status == 'FULFILLED';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: order.number,
              subtitle: order.customerName ?? s.walkInCustomer,
              trailing: StatusChip(status: order.status),
              child: Column(
                children: <Widget>[
                  _InfoRow(
                    label: s.warehouse,
                    value: order.warehouseName ?? '—',
                  ),
                  _InfoRow(
                    label: s.channel,
                    value: s.status(order.channel),
                  ),
                  _InfoRow(
                    label: s.orderDate,
                    value: Formatters.date(order.orderDate),
                  ),
                  if (order.fulfilledAt != null)
                    _InfoRow(
                      label: s.fulfilled,
                      value: Formatters.date(order.fulfilledAt),
                    ),
                  if (order.notes != null && order.notes!.isNotEmpty)
                    _InfoRow(label: s.notes, value: order.notes!),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: s.lines,
              subtitle: s.lineCount(order.lines.length),
              child: order.lines.isEmpty
                  ? Text(
                      s.noLinesOnOrder,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    )
                  : Column(
                      children: <Widget>[
                        for (final line in order.lines)
                          _LineTile(
                            name: line.productName ?? s.product,
                            sku: line.sku,
                            quantity: line.quantity,
                            fulfilled: line.fulfilledQty,
                            unitPrice: line.unitPrice,
                            currencyCode: order.currencyCode,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: s.totals,
              child: Column(
                children: <Widget>[
                  _TotalRow(
                    label: s.subtotal,
                    amount: order.subtotal,
                    currencyCode: order.currencyCode,
                  ),
                  _TotalRow(
                    label: s.discountWord,
                    amount: -order.discountTotal,
                    currencyCode: order.currencyCode,
                  ),
                  _TotalRow(
                    label: s.tax,
                    amount: order.taxTotal,
                    currencyCode: order.currencyCode,
                  ),
                  const Divider(),
                  _TotalRow(
                    label: s.total,
                    amount: order.total,
                    currencyCode: order.currencyCode,
                    emphasise: true,
                  ),
                ],
              ),
            ),
            if (canManage) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  if (canConfirm)
                    FilledButton.tonalIcon(
                      onPressed: _busy
                          ? null
                          : () => _act(
                                'confirm',
                                confirmTitle: s.confirmSalesOrderQ,
                                confirmMessage: s.confirmSalesOrderMessage,
                                successMessage: s.salesOrderConfirmed,
                              ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(s.confirmWord),
                    ),
                  if (canFulfill)
                    FilledButton.icon(
                      onPressed: _busy ? null : _fulfill,
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: Text(s.fulfil),
                    ),
                  if (canEdit)
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(s.edit),
                    ),
                  if (canInvoice)
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _createInvoice,
                      icon: const Icon(Icons.description_outlined),
                      label: Text(s.createInvoice),
                    ),
                  if (canCancel)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _act(
                                'cancel',
                                confirmTitle: s.cancelSalesOrderQ,
                                confirmMessage:
                                    order.status == 'FULFILLED' ||
                                            order.status ==
                                                'PARTIALLY_FULFILLED'
                                        ? s.cancelFulfilledOrderMessage
                                        : s.cannotBeUndone,
                                successMessage: s.salesOrderCancelled,
                                closeOnSuccess: true,
                              ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(s.cancel),
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
    required this.name,
    required this.sku,
    required this.quantity,
    required this.fulfilled,
    required this.unitPrice,
    this.currencyCode,
  });

  final String name;
  final String? sku;
  final int quantity;
  final int fulfilled;
  final double unitPrice;
  final String? currencyCode;

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
                Text(name, style: theme.textTheme.bodyLarge),
                Text(
                  '${sku ?? '—'} · ${s.lineQtyFulfilled(quantity, fulfilled)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          MoneyText(
            unitPrice,
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
