import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/return_order.dart';
import '../../state/returns_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_view.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../shell/navigation.dart';
import 'return_order_form_screen.dart';

/// Read-only return order with post / cancel actions.
class ReturnOrderDetailScreen extends StatefulWidget {
  const ReturnOrderDetailScreen({
    super.key,
    required this.orderId,
    this.initial,
  });

  final String orderId;
  final ReturnOrder? initial;

  @override
  State<ReturnOrderDetailScreen> createState() =>
      _ReturnOrderDetailScreenState();
}

class _ReturnOrderDetailScreenState extends State<ReturnOrderDetailScreen> {
  ReturnOrder? _order;
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
      final data = await api.getObject('/returns/${widget.orderId}');
      if (!mounted) return;
      setState(() => _order = ReturnOrder.fromJson(data));
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
        '/returns/${widget.orderId}/$action',
        body: const <String, dynamic>{},
      );
      await _load();
      // Keep the list screen in sync when we return to it.
      if (mounted) {
        await context.read<ReturnsController>().refresh();
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(successMessage ?? context.s.returnOrderCreated)),
      );
      if (closeOnSuccess) navigator.pop(true);
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
      context.s.editReturnOrder,
      ReturnOrderFormScreen(order: order),
    );
    if (saved == true && mounted) await _load();
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
          message: _error ?? s.noReturnsYet,
          onRetry: _load,
        ),
      );
    }

    final session = context.watch<Session>();
    final canManage = session.canAny(const <String>['sales', 'purchases']);
    final canEdit = session.can('returns.edit');
    final canCancelPosted = session.can('returns.cancel');
    final theme = Theme.of(context);
    final canPost = order.isDraft;
    final canCancel = order.isDraft || (order.isPosted && canCancelPosted);
    final canEditOrder =
        order.status != 'CANCELLED' && (order.isDraft || canEdit);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: order.number,
              subtitle:
                  '${order.isCustomerReturn ? s.customerReturns : s.supplierReturns} · '
                  '${order.partnerName}',
              trailing: StatusChip(status: order.status),
              child: Column(
                children: <Widget>[
                  _InfoRow(
                    label: s.returnType,
                    value: order.isCustomerReturn
                        ? s.customerReturns
                        : s.supplierReturns,
                  ),
                  _InfoRow(label: s.partner, value: order.partnerName),
                  _InfoRow(
                    label: s.warehouse,
                    value: order.warehouseName ?? order.warehouseCode ?? '—',
                  ),
                  _InfoRow(
                    label: s.orderDate,
                    value: Formatters.date(order.returnDate),
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
                          _LineTile(line: line),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: s.totals,
              child: Column(
                children: <Widget>[
                  _TotalRow(label: s.subtotal, amount: order.subtotal),
                  _TotalRow(label: s.tax, amount: order.taxTotal),
                  const Divider(),
                  _TotalRow(
                    label: s.total,
                    amount: order.total,
                    emphasise: true,
                  ),
                ],
              ),
            ),
            if (canManage && (canPost || canCancel || canEditOrder)) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  if (canEditOrder)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(s.edit),
                    ),
                  if (canPost)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _act(
                                'post',
                                confirmTitle: s.postReturnQ,
                                confirmMessage: s.postReturnHint(order.number),
                                successMessage: s.returnPosted,
                              ),
                      icon: const Icon(Icons.done_all_outlined),
                      label: Text(s.postReturn),
                    ),
                  if (canCancel)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _act(
                                'cancel',
                                confirmTitle: s.cancelReturnQ,
                                confirmMessage: s.cannotBeUndone,
                                successMessage: s.returnCancelled,
                                closeOnSuccess: true,
                              ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(s.cancelReturn),
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
  const _LineTile({required this.line});

  final ReturnLine line;

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
                Text(line.productName ?? s.product, style: theme.textTheme.bodyLarge),
                Text(
                  '${line.sku ?? '—'} · ${s.qty}: ${line.quantity}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          MoneyText(
            line.lineTotal,
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
    this.emphasise = false,
  });

  final String label;
  final double amount;
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
            style: style?.copyWith(
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
