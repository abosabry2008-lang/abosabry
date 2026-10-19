import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/cash_box.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// Creates or edits a cash box (خزنة).
class BoxFormScreen extends StatefulWidget {
  const BoxFormScreen({super.key, this.box});

  /// `null` creates a new box.
  final CashBox? box;

  @override
  State<BoxFormScreen> createState() => _BoxFormScreenState();
}

class _BoxFormScreenState extends State<BoxFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.box?.name ?? '');
  late final TextEditingController _code =
      TextEditingController(text: widget.box?.code ?? '');
  late final TextEditingController _opening = TextEditingController(
    text: widget.box == null ? '0' : widget.box!.openingBalance.toStringAsFixed(2),
  );

  late String _type = widget.box?.type ?? 'SUB';
  late bool _isDefault = widget.box?.isDefault ?? false;
  late bool _active = widget.box?.active ?? true;
  bool _saving = false;

  bool get _editing => widget.box != null;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final s = context.s;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'code': _code.text.trim().toUpperCase(),
      'type': _type,
      'openingBalance': double.tryParse(_opening.text.trim()) ?? 0,
      'isDefault': _isDefault,
      'active': _active,
    };
    try {
      if (_editing) {
        await api.patchObject('/treasury/boxes/${widget.box!.id}', body: body);
      } else {
        await api.postObject('/treasury/boxes', body: body);
      }
      messenger.showSnackBar(SnackBar(content: Text(s.boxSaved)));
      navigator.pop(true);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: _editing ? s.editCashBox : s.newCashBox,
            child: Column(
              children: <Widget>[
                AppTextField(
                  label: s.cashBoxName,
                  controller: _name,
                  enabled: !_saving,
                  prefixIcon: Icons.account_balance_wallet_outlined,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? s.nameRequired
                      : null,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: s.code,
                  controller: _code,
                  enabled: !_saving && !_editing,
                  hint: 'MAIN',
                  prefixIcon: Icons.qr_code_2,
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? s.codeRequired
                      : null,
                ),
                const SizedBox(height: 14),
                AppSelectField<String>(
                  label: s.cashBoxType,
                  value: _type,
                  enabled: !_saving,
                  prefixIcon: Icons.category_outlined,
                  options: <SelectOption<String>>[
                    SelectOption<String>('MAIN', s.mainBox),
                    SelectOption<String>('SUB', s.subBox),
                  ],
                  onChanged: (value) =>
                      setState(() => _type = value ?? _type),
                ),
                const SizedBox(height: 14),
                AppNumberField(
                  label: s.openingBalance,
                  controller: _opening,
                  enabled: !_saving,
                  prefixIcon: Icons.savings_outlined,
                  helperText: s.currentBalance,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: s.settings,
            child: Column(
              children: <Widget>[
                AppSwitchField(
                  label: s.setAsDefault,
                  value: _isDefault,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _isDefault = value),
                ),
                const SizedBox(height: 8),
                AppSwitchField(
                  label: s.active,
                  value: _active,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _active = value),
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
        ],
      ),
    );
  }
}
