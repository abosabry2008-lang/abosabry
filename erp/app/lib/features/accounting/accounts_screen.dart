import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/account.dart';
import '../../state/accounting_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

/// Chart of accounts with a trial-balance style debit/credit view.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  String? _type;

  Future<void> _createAccount() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AccountFormDialog(),
    );
    if (created == true && mounted) {
      context.read<AccountsController>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<AccountsController>();
    final canWrite = context.watch<Session>().can('accounting');
    final rows = _type == null
        ? controller.items
        : controller.items.where((account) => account.type == _type).toList();

    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AppSelectField<String>(
              label: s.accountType,
              value: _type,
              hint: s.allTypes,
              options: <SelectOption<String>>[
                SelectOption<String>('', s.allTypes),
                ...Account.types.map(
                  (type) => SelectOption<String>(type, s.status(type)),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _type = (value == null || value.isEmpty) ? null : value),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncListView<Account>(
              controller: controller,
              emptyIcon: Icons.account_balance_outlined,
              emptyTitle: s.noAccounts,
              emptyMessage: s.chartCreatedHint,
              itemBuilder: (context, account, index) {
                if (_type != null && account.type != _type) {
                  return const SizedBox.shrink();
                }
                return SectionCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        account.code.isEmpty ? '?' : account.code,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    title: Text(account.name),
                    subtitle: Text(s.status(account.type)),
                    trailing: StatusChip(
                      status: account.active ? 'ACTIVE' : 'INACTIVE',
                      label: account.active ? s.active : s.inactive,
                      compact: true,
                    ),
                  ),
                );
              },
            ),
          ),
          if (rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                s.accountCount(rows.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _createAccount,
              icon: const Icon(Icons.add),
              label: Text(s.accountWord),
            )
          : null,
    );
  }
}

class _AccountFormDialog extends StatefulWidget {
  const _AccountFormDialog();

  @override
  State<_AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends State<_AccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  String _type = 'ASSET';
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await api.post('/accounting/accounts', body: <String, dynamic>{
        'code': _code.text.trim(),
        'name': _name.text.trim(),
        'type': _type,
      });
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.s.accountCreated)),
      );
      navigator.pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AlertDialog(
      title: Text(s.newAccount),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppTextField(
                label: s.code,
                controller: _code,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? s.codeRequired : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: s.name,
                controller: _name,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? s.nameRequired : null,
              ),
              const SizedBox(height: 12),
              AppSelectField<String>(
                label: s.type,
                value: _type,
                options: Account.types
                    .map(
                      (type) => SelectOption<String>(type, s.status(type)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? s.saving : s.create),
        ),
      ],
    );
  }
}
