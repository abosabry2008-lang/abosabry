import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/permissions_catalog.dart';
import '../../core/session.dart';
import '../../models/user.dart';
import '../../state/users_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

const List<String> userRoles = <String>[
  'ADMIN',
  'MANAGER',
  'SALES',
  'CASHIER',
  'WAREHOUSE',
  'ACCOUNTANT',
];

/// User administration tab: list, create, edit and deactivate.
/// Embedded inside the Settings screen (Users tab, admin-only).
class UsersTab extends StatelessWidget {
  const UsersTab({super.key});

  Future<void> _openForm(BuildContext context, {AppUser? user}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(user: user),
    );
    if (saved == true && context.mounted) {
      context.read<UsersController>().refresh();
    }
  }

  Future<void> _deactivate(BuildContext context, AppUser user) async {
    final confirmed = await confirmDialog(
      context,
      title: context.s.deactivateUserQ(user.name),
      message: context.s.deactivateUserMessage,
      confirmLabel: context.s.deactivate,
    );
    if (!confirmed || !context.mounted) return;
    final s = context.s;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<UsersController>();
    try {
      await api.delete('/users/${user.id}');
      messenger.showSnackBar(
        SnackBar(content: Text(s.userDeactivated)),
      );
      controller.refresh();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<UsersController>();
    final canWrite = context.watch<Session>().can('users');
    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: <Widget>[
                AppSearchField(
                  hintText: s.searchUsersHint,
                  initialValue: controller.search,
                  onChanged: controller.searchWith,
                ),
                const SizedBox(height: 8),
                AppSelectField<String>(
                  label: s.role,
                  value: controller.role,
                  hint: s.allRoles,
                  options: <SelectOption<String>>[
                    SelectOption<String>('', s.allRoles),
                    ...userRoles.map(
                      (role) => SelectOption<String>(role, s.status(role)),
                    ),
                  ],
                  onChanged: (value) => controller.filterByRole(
                    value == null || value.isEmpty ? null : value,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncListView<AppUser>(
              controller: controller,
              emptyIcon: Icons.people_outline,
              emptyTitle: s.noUsers,
              emptyMessage: s.inviteUserHint,
              itemBuilder: (context, user, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                    ),
                  ),
                  title: Text(user.name),
                  subtitle: Text(user.email),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      StatusChip(
                        status: user.active ? 'ACTIVE' : 'INACTIVE',
                        label: s.status(user.role),
                        compact: true,
                      ),
                      if (canWrite)
                        SizedBox(
                          height: 28,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: s.edit,
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _openForm(context, user: user),
                              ),
                              if (user.active)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: s.deactivate,
                                  icon: const Icon(
                                    Icons.person_off_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () => _deactivate(context, user),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  onTap: canWrite ? () => _openForm(context, user: user) : null,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.person_add_outlined),
              label: Text(s.user),
            )
          : null,
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({this.user});

  final AppUser? user;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.user?.name ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.user?.email ?? '');
  final _password = TextEditingController();
  late final TextEditingController _phone =
      TextEditingController(text: widget.user?.phone ?? '');
  late String _role = widget.user?.role ?? 'SALES';
  late bool _active = widget.user?.active ?? true;
  Set<String> _customPerms = <String>{};
  bool _useCustom = false;
  bool _obscure = false;
  bool _saving = false;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit && widget.user?.permissions != null) {
      _useCustom = widget.user!.permissions!.isNotEmpty;
      _customPerms = widget.user!.permissions!.toSet();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'role': _role,
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'active': _active,
      if (_password.text.isNotEmpty) 'password': _password.text,
      'permissions': _useCustom ? _customPerms.toList() : null,
    };
    try {
      if (_isEdit) {
        await api.patch('/users/${widget.user!.id}', body: body);
      } else {
        await api.post('/users', body: body);
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEdit ? context.s.userUpdated : context.s.userCreated),
        ),
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
      title: Text(_isEdit ? s.editUser : s.newUser),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppTextField(
                label: s.name,
                controller: _name,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? s.nameRequired : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: s.email,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final email = (value ?? '').trim();
                  if (email.isEmpty) return s.emailRequired;
                  if (!email.contains('@')) return s.enterValidEmail;
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: _isEdit ? s.newPasswordOptional : s.password,
                controller: _password,
                obscureText: _obscure,
                suffix: IconButton(
                  tooltip: _obscure ? s.showPassword : s.hidePassword,
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                validator: (value) {
                  final password = value ?? '';
                  if (_isEdit && password.isEmpty) return null;
                  if (password.length < 8) {
                    return s.useAtLeast8;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: s.phone,
                controller: _phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              AppSelectField<String>(
                label: s.role,
                value: _role,
                options: userRoles
                    .map(
                      (role) => SelectOption<String>(role, s.status(role)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _role = value);
                },
              ),
              const SizedBox(height: 8),
              AppSwitchField(
                label: s.active,
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
              const SizedBox(height: 12),
              AppSwitchField(
                label: 'استخدام صلاحيات مخصصة',
                value: _useCustom,
                onChanged: (value) => setState(() => _useCustom = value),
              ),
              if (_useCustom) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 320,
                  width: double.maxFinite,
                  child: ListView(
                    children: [
                      for (final entry in PermissionCatalog.groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            entry.key,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        for (final p in entry.value)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.label),
                            subtitle: Text(p.key),
                            value: _customPerms.contains(p.key),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _customPerms.add(p.key);
                                } else {
                                  _customPerms.remove(p.key);
                                }
                              });
                            },
                          ),
                        const Divider(),
                      ],
                    ],
                  ),
                ),
              ],
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
          child: Text(_saving ? s.saving : s.save),
        ),
      ],
    );
  }
}
