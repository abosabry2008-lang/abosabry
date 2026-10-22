import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/cash_box.dart';
import '../../models/cash_transfer.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// Creates or edits a transfer between two cash boxes.
class TransferFormScreen extends StatefulWidget {
  const TransferFormScreen({
    super.key,
    this.transfer,
    this.boxes = const <CashBox>[],
    this.initialFromBoxId,
    this.initialToBoxId,
  });

  /// When set the form edits an existing transfer (amount/date/note only).
  final CashTransfer? transfer;
  final List<CashBox> boxes;
  final String? initialFromBoxId;
  final String? initialToBoxId;

  @override
  State<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends State<TransferFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _amount = TextEditingController(
    text: widget.transfer == null
        ? ''
        : Formatters.number(widget.transfer!.amount),
  );
  late final TextEditingController _reference =
      TextEditingController(text: widget.transfer?.reference ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.transfer?.note ?? '');

  List<CashBox> _boxes = <CashBox>[];
  String? _fromId;
  String? _toId;
  late DateTime _date = widget.transfer?.transferDate ?? DateTime.now();
  bool _loading = true;
  bool _saving = false;

  bool get _editing => widget.transfer != null;

  @override
  void initState() {
    super.initState();
    _fromId = widget.transfer?.fromBoxId ?? widget.initialFromBoxId;
    _toId = widget.transfer?.toBoxId ?? widget.initialToBoxId;
    _boxes = widget.boxes;
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_boxes.isEmpty) {
      try {
        final rows =
            await context.read<Session>().api.getList('/treasury/boxes');
        if (!mounted) return;
        _boxes = rows.map(CashBox.fromJson).toList();
      } on ApiException {
        // Keep whatever boxes we were given.
      }
    }
    if (!mounted) return;
    setState(() {
      _fromId ??= _boxes.isNotEmpty ? _boxes.first.id : null;
      _toId ??= _boxes.length > 1
          ? _boxes.firstWhere(
              (box) => box.id != _fromId,
              orElse: () => _boxes.first,
            ).id
          : null;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final s = context.s;
    if (!_editing && (_fromId == null || _toId == null || _fromId == _toId)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.sameBox)));
      return;
    }
    setState(() => _saving = true);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      if (_editing) {
        await api.patchObject(
          '/treasury/transfers/${widget.transfer!.id}',
          body: <String, dynamic>{
            'amount': double.tryParse(_amount.text.trim()) ?? 0,
            'transferDate': _date.toIso8601String(),
            'reference':
                _reference.text.trim().isEmpty ? null : _reference.text.trim(),
            'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
          },
        );
        messenger.showSnackBar(SnackBar(content: Text(s.transferUpdated)));
      } else {
        await api.postObject(
          '/treasury/transfers',
          body: <String, dynamic>{
            'fromBoxId': _fromId,
            'toBoxId': _toId,
            'amount': double.tryParse(_amount.text.trim()) ?? 0,
            'transferDate': _date.toIso8601String(),
            'reference':
                _reference.text.trim().isEmpty ? null : _reference.text.trim(),
            'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
          },
        );
        messenger.showSnackBar(SnackBar(content: Text(s.transferSaved)));
      }
      navigator.pop(true);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelTransfer() async {
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
    final navigator = Navigator.of(context);
    try {
      await api.post('/treasury/transfers/${widget.transfer!.id}/cancel');
      messenger.showSnackBar(SnackBar(content: Text(s.transferCancelled)));
      navigator.pop(true);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final options = _boxes
        .where((box) => box.active)
        .map(
          (box) => SelectOption<String>(
            box.id,
            '${box.name} · ${Formatters.money(box.balance)}',
          ),
        )
        .toList();

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: _editing ? s.editTransfer : s.newTransfer,
            child: Column(
              children: <Widget>[
                if (!_editing) ...<Widget>[
                  AppSelectField<String>(
                    label: s.fromBox,
                    value: _fromId,
                    hint: s.chooseBox,
                    enabled: !_saving,
                    prefixIcon: Icons.logout,
                    options: options,
                    validator: (value) => value == null ? s.chooseBox : null,
                    onChanged: (value) => setState(() => _fromId = value),
                  ),
                  const SizedBox(height: 14),
                  AppSelectField<String>(
                    label: s.toBox,
                    value: _toId,
                    hint: s.chooseBox,
                    enabled: !_saving,
                    prefixIcon: Icons.login,
                    options: options,
                    validator: (value) => value == null ? s.chooseBox : null,
                    onChanged: (value) => setState(() => _toId = value),
                  ),
                  const SizedBox(height: 14),
                ],
                AppNumberField(
                  label: s.transferAmount,
                  controller: _amount,
                  enabled: !_saving,
                  prefixIcon: Icons.swap_horiz,
                  validator: (value) {
                    final parsed = double.tryParse((value ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return s.enterAmountGreaterThanZero;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                AppDateField(
                  label: s.date,
                  value: _date,
                  enabled: !_saving,
                  clearable: false,
                  onChanged: (value) {
                    if (value != null) setState(() => _date = value);
                  },
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: s.reference,
                  controller: _reference,
                  enabled: !_saving,
                  prefixIcon: Icons.tag_outlined,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: s.note,
                  controller: _note,
                  enabled: !_saving,
                  maxLines: 2,
                  prefixIcon: Icons.notes_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  child: Text(s.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: const Icon(Icons.check),
                  label: Text(_saving ? s.saving : s.save),
                ),
              ),
            ],
          ),
          if (_editing && context.watch<Session>().isAdmin) ...<Widget>[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _saving ? null : _cancelTransfer,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.cancel_outlined),
              label: Text(s.cancelTransferQ),
            ),
          ],
        ],
      ),
    );
  }
}
