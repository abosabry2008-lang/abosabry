import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/purchase_order.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_view.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../shell/navigation.dart';
import 'purchase_order_edit_screen.dart';

/// Read-only purchase order with approve / receive / cancel actions.
class PurchaseOrderDetailScreen extends StatefulWidget {
  const PurchaseOrderDetailScreen({
    super.key,
    required this.orderId,
    this.initial,
  });

  final String orderId;
  final PurchaseOrder? initial;

  @override
  State<PurchaseOrderDetailScreen> createState() =>
      _PurchaseOrderDetailScreenState();
}

class _PurchaseOrderDetailScreenState extends State<PurchaseOrderDetailScreen> {
  PurchaseOrder? _order;
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
      final data = await api.getObject('/purchase-orders/${widget.orderId}');
      if (!mounted) return;
      setState(() => _order = PurchaseOrder.fromJson(data));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final order = _order;
    if (order == null) return;
    final saved = await pushScreen<bool>(
      context,
      context.s.editOrder,
      PurchaseOrderEditScreen(order: order),
    );
    if (saved == true) await _load();
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
        '/purchase-orders/${widget.orderId}/$action',
        body: const <String, dynamic>{},
      );
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(successMessage ?? context.s.purchaseOrderUpdated)),
      );
      if (closeOnSuccess) navigator.pop(true);
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
          message: _error ?? s.purchaseOrderNotFound,
          onRetry: _load,
        ),
      );
    }

    final session = context.watch<Session>();
    final canManage = session.can('purchases');
    final canCancelOrder = session.can('purchases.cancel');
    final theme = Theme.of(context);
    final canApprove = order.status == 'DRAFT' || order.status == 'PENDING';
    final canReceive =
        order.status == 'APPROVED' || order.status == 'PARTIALLY_RECEIVED';
    final hasReceived = order.lines.any((line) => line.receivedQty > 0);
    // Admins can cancel or edit any order that is not already cancelled —
    // including received ones, whose goods, payable and ledger entry are
    // reversed automatically by the API.
    final canCancel =
        order.status != 'CANCELLED' && session.isAdmin;
    final canEdit = order.status != 'CANCELLED' &&
        ((order.status == 'DRAFT' && canManage) || canCancelOrder);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: order.number,
              subtitle: order.supplierName ?? s.supplier,
              trailing: StatusChip(status: order.status),
              child: Column(
                children: <Widget>[
                  _InfoRow(
                    label: s.warehouse,
                    value: order.warehouseName ?? '—',
                  ),
                  _InfoRow(
                    label: s.orderDate,
                    value: Formatters.date(order.orderDate),
                  ),
                  _InfoRow(
                    label: s.expected,
                    value: Formatters.date(order.expectedDate),
                  ),
                  if (order.receivedAt != null)
                    _InfoRow(
                      label: s.received,
                      value: Formatters.date(order.receivedAt),
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
                            received: line.receivedQty,
                            unitPrice: line.unitCost,
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
            if ((canManage || canCancelOrder) &&
                (canApprove || canReceive || canCancel || canEdit)) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  if (canEdit)
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(s.edit),
                    ),
                  if (canApprove)
                    FilledButton.tonalIcon(
                      onPressed: _busy
                          ? null
                          : () => _act(
                                'approve',
                                confirmTitle: s.approvePurchaseOrderQ,
                                confirmMessage: s.approvePurchaseOrderMessage,
                                successMessage: s.purchaseOrderApproved,
                              ),
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(s.approve),
                    ),
                  if (canReceive)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _act(
                                'receive',
                                confirmTitle: s.receiveAllOutstandingQ,
                                confirmMessage: s.receiveAllOutstandingMessage,
                                successMessage: s.stockReceived,
                              ),
                      icon: const Icon(Icons.download_outlined),
                      label: Text(s.receive),
                    ),
                  if (canCancel && canCancelOrder)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _act(
                                'cancel',
                                confirmTitle: s.cancelPurchaseOrderQ,
                                confirmMessage: hasReceived
                                    ? s.cancelReceivedOrderMessage
                                    : s.cannotBeUndone,
                                successMessage: s.purchaseOrderCancelled,
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
    required this.received,
    required this.unitPrice,
    this.currencyCode,
  });

  final String name;
  final String? sku;
  final int quantity;
  final int received;
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
                  '${sku ?? '—'} · ${s.lineQtyReceived(quantity, received)}',
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
