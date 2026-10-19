import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/box_statement.dart';
import '../../models/cash_box.dart';
import '../../models/cash_transfer.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/date_range_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/money_text.dart';
import '../payments/payment_form_screen.dart';
import '../shell/navigation.dart';
import 'box_form_screen.dart';
import 'transfer_form_screen.dart';

/// Statement of account for one cash box with deposit / withdraw actions and
/// (for admins) edit / cancel of every movement.
class BoxDetailScreen extends StatefulWidget {
  const BoxDetailScreen({super.key, required this.boxId, this.initialBox});

  final String boxId;
  final CashBox? initialBox;

  @override
  State<BoxDetailScreen> createState() => _BoxDetailScreenState();
}

class _BoxDetailScreenState extends State<BoxDetailScreen> {
  CashBox? _box;
  BoxStatement? _statement;
  DateTime? _from;
  DateTime? _to;
  bool _loading = true;
  String? _error;

  bool get _hasRange => _from != null || _to != null;

  @override
  void initState() {
    super.initState();
    _box = widget.initialBox;
    _load();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await api.getObject(
        '/treasury/boxes/${widget.boxId}/statement',
        query: <String, dynamic>{
          if (_from != null) 'from': Formatters.isoDate(_from!),
          if (_to != null) 'to': Formatters.isoDate(_to!),
        },
      );
      if (!mounted) return;
      final statement = BoxStatement.fromJson(json);
      setState(() {
        _statement = statement;
        _box = statement.box;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deposit() async {
    final created = await pushScreen<bool>(
      context,
      context.s.depositIntoBox,
      PaymentFormScreen(
        direction: 'INBOUND',
        cashBoxId: widget.boxId,
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _withdraw() async {
    final created = await pushScreen<bool>(
      context,
      context.s.withdrawFromBox,
      PaymentFormScreen(
        direction: 'OUTBOUND',
        cashBoxId: widget.boxId,
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _transfer() async {
    final created = await pushScreen<bool>(
      context,
      context.s.newTransfer,
      TransferFormScreen(initialFromBoxId: widget.boxId),
    );
    if (created == true) await _load();
  }

  Future<void> _editBox() async {
    final box = _box;
    if (box == null) return;
    final saved = await pushScreen<bool>(
      context,
      context.s.editCashBox,
      BoxFormScreen(box: box),
    );
    if (saved == true) await _load();
  }

  Future<void> _editPayment(BoxStatementRow row) async {
    final paymentId = row.paymentId;
    if (paymentId == null) return;
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditPaymentDialog(
        amount: row.amount,
        reference: row.reference,
        description: row.description,
      ),
    );
    if (body == null || !mounted) return;
    final s = context.s;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.patchObject('/payments/$paymentId', body: body);
      messenger.showSnackBar(
        SnackBar(content: Text(s.paymentUpdated)),
      );
      await _load();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _cancelPayment(BoxStatementRow row) async {
    final paymentId = row.paymentId;
    if (paymentId == null) return;
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.cancelPaymentQ,
      message: s.cancelPaymentMessage,
      destructive: true,
      confirmLabel: s.cancel,
    );
    if (!confirmed || !mounted) return;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post('/payments/$paymentId/cancel');
      messenger.showSnackBar(SnackBar(content: Text(s.paymentCancelled)));
      await _load();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _editTransfer(BoxStatementRow row) async {
    final transferId = row.transferId;
    if (transferId == null) return;
    final transfer = CashTransfer(
      id: transferId,
      number: row.number,
      fromBoxId: widget.boxId,
      toBoxId: widget.boxId,
      amount: row.amount,
      reference: row.reference,
      transferDate: row.date,
    );
    final saved = await pushScreen<bool>(
      context,
      context.s.editTransfer,
      TransferFormScreen(transfer: transfer),
    );
    if (saved == true) await _load();
  }

  Future<void> _cancelTransfer(BoxStatementRow row) async {
    final transferId = row.transferId;
    if (transferId == null) return;
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.cancelTransferQ,
      destructive: true,
      confirmLabel: s.cancel,
    );
    if (!confirmed || !mounted) return;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post('/treasury/transfers/$transferId/cancel');
      messenger.showSnackBar(SnackBar(content: Text(s.transferCancelled)));
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
    final session = context.watch<Session>();
    final canManage = session.can('treasury.manage');
    final canPay = session.can('payments');

    if (_loading && _statement == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _statement == null) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    final statement = _statement;
    final box = _box;
    final balance = statement?.closingBalance ?? box?.balance ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: <Color>[
                  scheme.primary.withValues(alpha: 0.92),
                  scheme.primary.withValues(alpha: 0.65),
                ],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      (box?.isMain ?? false)
                          ? Icons.account_balance
                          : Icons.savings_outlined,
                      color: scheme.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        box?.name ?? '',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: scheme.onPrimary),
                      ),
                    ),
                    if (box != null && box.isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.onPrimary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          s.defaultBox,
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  s.currentBalance,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                MoneyText(
                  balance,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (canPay)
                      FilledButton.tonalIcon(
                        onPressed: _deposit,
                        icon: const Icon(Icons.arrow_downward, size: 18),
                        label: Text(s.deposit),
                      ),
                    if (canPay)
                      FilledButton.tonalIcon(
                        onPressed: _withdraw,
                        icon: const Icon(Icons.arrow_upward, size: 18),
                        label: Text(s.withdraw),
                      ),
                    if (canManage)
                      OutlinedButton.icon(
                        onPressed: _transfer,
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: Text(s.transfer),
                      ),
                    if (canManage)
                      OutlinedButton.icon(
                        onPressed: _editBox,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(s.edit),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
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
              if (_hasRange)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _from = null;
                      _to = null;
                    });
                    _load();
                  },
                  icon: const Icon(Icons.clear, size: 18),
                  label: Text(s.clear),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (statement != null)
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _Summary(
                        label: s.openingBalance,
                        value: statement.openingBalance,
                      ),
                    ),
                    Expanded(
                      child: _Summary(
                        label: s.totalIn,
                        value: statement.inTotal,
                        color: Colors.green.shade700,
                        prefix: '+',
                      ),
                    ),
                    Expanded(
                      child: _Summary(
                        label: s.totalOut,
                        value: statement.outTotal,
                        color: scheme.error,
                        prefix: '-',
                      ),
                    ),
                    Expanded(
                      child: _Summary(
                        label: s.closingBalance,
                        value: statement.closingBalance,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: <Widget>[
                Text(s.statement, style: theme.textTheme.titleSmall),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    '${statement?.rows.length ?? 0}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
              ],
            ),
          ),
          if (statement == null || statement.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: EmptyState(
                icon: Icons.swap_vert,
                title: s.noMovements,
              ),
            )
          else
            ...statement.rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _StatementRowTile(
                  row: row,
                  canManage: canManage,
                  onEdit: row.isPayment
                      ? () => _editPayment(row)
                      : () => _editTransfer(row),
                  onCancel: row.isPayment
                      ? () => _cancelPayment(row)
                      : () => _cancelTransfer(row),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.value,
    this.color,
    this.prefix,
  });

  final String label;
  final double value;
  final Color? color;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            if (prefix != null)
              Text(prefix!, style: TextStyle(color: color)),
            Flexible(
              child: MoneyText(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatementRowTile extends StatelessWidget {
  const _StatementRowTile({
    required this.row,
    required this.canManage,
    required this.onEdit,
    required this.onCancel,
  });

  final BoxStatementRow row;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = row.isIn ? Colors.green.shade700 : scheme.error;
    final label = switch (row.type) {
      'PAYMENT_IN' => s.paymentIn,
      'PAYMENT_OUT' => s.paymentOut,
      'TRANSFER_IN' => s.transferIn,
      'TRANSFER_OUT' => s.transferOut,
      _ => row.type,
    };

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(
                row.isIn ? Icons.south_west : Icons.north_east,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.description.isEmpty ? label : row.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      row.number,
                      label,
                      if (row.method != null) s.status(row.method),
                      Formatters.date(row.date),
                    ].where((part) => part.isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                MoneyText(
                  row.isIn ? row.amount : -row.amount,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                MoneyText(
                  row.balance,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ],
            ),
            if (canManage)
              PopupMenuButton<String>(
                tooltip: s.edit,
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'cancel') onCancel();
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(s.edit),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'cancel',
                    child: ListTile(
                      leading: Icon(Icons.cancel_outlined, color: scheme.error),
                      title: Text(s.cancel),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              )
            else
              const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _EditPaymentDialog extends StatefulWidget {
  const _EditPaymentDialog({
    required this.amount,
    this.reference,
    this.description,
  });

  final double amount;
  final String? reference;
  final String? description;

  @override
  State<_EditPaymentDialog> createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends State<_EditPaymentDialog> {
  late final TextEditingController _amount =
      TextEditingController(text: Formatters.number(widget.amount));
  late final TextEditingController _reference =
      TextEditingController(text: widget.reference ?? '');
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AlertDialog(
      title: Text(s.editPayment),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  widget.description!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: s.amount,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: InputDecoration(
                labelText: s.reference,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: InputDecoration(
                labelText: s.note,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amount.text.trim());
            if (amount == null || amount <= 0) return;
            Navigator.of(context).pop(<String, dynamic>{
              'amount': amount,
              'reference':
                  _reference.text.trim().isEmpty ? null : _reference.text.trim(),
              'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
            });
          },
          child: Text(s.save),
        ),
      ],
    );
  }
}
