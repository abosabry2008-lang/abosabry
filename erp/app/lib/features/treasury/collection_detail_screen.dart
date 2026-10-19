import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/collection_voucher.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_view.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';

/// Read-only collection receipt with a cancel action for admins.
class CollectionDetailScreen extends StatefulWidget {
  const CollectionDetailScreen({
    super.key,
    required this.voucherId,
    this.initial,
  });

  final String voucherId;
  final CollectionVoucher? initial;

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  CollectionVoucher? _voucher;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _voucher = widget.initial;
    _load();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json =
          await api.getObject('/treasury/collections/${widget.voucherId}');
      if (!mounted) return;
      setState(() => _voucher = CollectionVoucher.fromJson(json));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.cancelCollectionQ,
      message: s.cancelCollectionMessage,
      destructive: true,
      confirmLabel: s.cancel,
    );
    if (!confirmed || !mounted) return;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post('/treasury/collections/${widget.voucherId}/cancel');
      messenger.showSnackBar(SnackBar(content: Text(s.collectionCancelled)));
      await _load();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final voucher = _voucher;

    if (_loading && voucher == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && voucher == null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (voucher == null) {
      return Center(child: Text(s.noCollections));
    }

    final canCancel =
        context.watch<Session>().can('treasury.manage') && !voucher.cancelled;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: voucher.cancelled
                  ? scheme.surfaceContainerHighest
                  : scheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.receipt_long_outlined,
                      color: voucher.cancelled
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        voucher.number,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: voucher.cancelled
                              ? scheme.onSurfaceVariant
                              : scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    if (voucher.cancelled)
                      Text(
                        s.status('VOID'),
                        style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  s.voucherTotal,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: voucher.cancelled
                        ? scheme.onSurfaceVariant
                        : scheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 2),
                MoneyText(
                  voucher.total,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: voucher.cancelled
                        ? scheme.onSurfaceVariant
                        : scheme.onPrimaryContainer,
                    decoration:
                        voucher.cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: s.details,
            child: Column(
              children: <Widget>[
                _InfoRow(label: s.date, value: Formatters.date(voucher.collectedAt)),
                _InfoRow(label: s.cashBox, value: voucher.cashBoxName),
                _InfoRow(
                  label: s.salesperson,
                  value: voucher.salespersonName.isEmpty
                      ? s.noSalesperson
                      : voucher.salespersonName,
                ),
                if (voucher.userName.isNotEmpty)
                  _InfoRow(label: s.erpUser, value: voucher.userName),
                if (voucher.reference != null)
                  _InfoRow(label: s.reference, value: voucher.reference!),
                if (voucher.note != null)
                  _InfoRow(label: s.note, value: voucher.note!),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: s.collectionLines,
            child: Column(
              children: <Widget>[
                for (final line in voucher.lines) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                line.customerName.isEmpty
                                    ? s.customer
                                    : line.customerName,
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                <String>[
                                  if (line.invoiceNumber != null)
                                    '${s.invoice} ${line.invoiceNumber}',
                                  if (line.cashBoxName.isNotEmpty)
                                    '${s.cashBox}: ${line.cashBoxName}',
                                  if (line.note != null) line.note!,
                                ].join(' · '),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: scheme.outline),
                              ),
                            ],
                          ),
                        ),
                        MoneyText(
                          line.amount,
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
                if (voucher.paymentNumbers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '${s.payments}: ${voucher.paymentNumbers.join('، ')}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.outline),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (canCancel) ...<Widget>[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error),
              ),
              icon: const Icon(Icons.cancel_outlined),
              label: Text(s.cancelCollectionQ),
            ),
          ],
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 130,
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
