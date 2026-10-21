import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/permissions_catalog.dart';
import '../../core/session.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

/// Lets the manager edit which permissions each role has.
/// Everything is picked with checkboxes — no manual key entry.
class RolePermissionsTab extends StatefulWidget {
  const RolePermissionsTab({super.key});

  @override
  State<RolePermissionsTab> createState() => _RolePermissionsTabState();
}

class _RolePermissionsTabState extends State<RolePermissionsTab> {
  String _role = PermissionCatalog.editableRoles.first;
  Set<String> _selected = <String>{};
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.get('/settings/role-permissions');
      final map = (data as Map).cast<String, dynamic>();
      final roles = (map['roles'] as List).cast<Map>();
      for (final entry in roles) {
        if (entry['role'] == _role) {
          _selected = (entry['permissions'] as List)
              .map((e) => e.toString())
              .toSet();
          break;
        }
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _switchRole(String role) async {
    if (role == _role) return;
    if (_dirty) {
      final confirmed = await confirmDialog(
        context,
        title: 'تغييرات غير محفوظة',
        message: 'فيه تعديلات لسه متحفظتش. تحب تسيبها وتسيب الصلاحيات القديمة؟',
        confirmLabel: 'سيب التغييرات',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() {
      _role = role;
      _dirty = false;
    });
    await _load();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.put(
        '/settings/role-permissions',
        body: <String, dynamic>{
          'role': _role,
          'permissions': _selected.toList(),
        },
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('اتحفظت صلاحيات ${context.s.status(_role)}')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _resetToDefault() async {
    final confirmed = await confirmDialog(
      context,
      title: 'استرجاع الصلاحيات الافتراضية',
      message: 'هيتم إرجاع صلاحيات ${context.s.status(_role)} للوضع الافتراضي.',
      confirmLabel: 'استرجع',
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.delete('/settings/role-permissions/$_role');
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('تم استرجاع الصلاحيات الافتراضية')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _setGroup(List<PermItem> items, bool value) {
    setState(() {
      for (final p in items) {
        if (value) {
          _selected.add(p.key);
        } else {
          _selected.remove(p.key);
        }
      }
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(s.retry)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SectionCard(
            title: 'صلاحيات الأدوار',
            subtitle:
                'حدد لكل دور إيه الشاشات والإجراءات المسموح بيها. الاختيار بالـCheckBox.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final role in PermissionCatalog.editableRoles)
                      ChoiceChip(
                        label: Text(s.status(role)),
                        selected: role == _role,
                        onSelected: (_) => _switchRole(role),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'محدد: ${_selected.length} من ${PermissionCatalog.allKeys().length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    StatusChip(
                      status: _dirty ? 'INACTIVE' : 'ACTIVE',
                      label: _dirty ? 'تعديلات غير محفوظة' : 'محفوظ',
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            children: <Widget>[
              for (final entry in PermissionCatalog.groups.entries)
                _GroupCard(
                  title: entry.key,
                  items: entry.value,
                  selected: _selected,
                  onToggleItem: (item, value) {
                    setState(() {
                      if (value) {
                        _selected.add(item.key);
                      } else {
                        _selected.remove(item.key);
                      }
                      _dirty = true;
                    });
                  },
                  onToggleAll: (value) => _setGroup(entry.value, value),
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _saving ? null : _resetToDefault,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('الافتراضي'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving || !_dirty ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? s.saving : s.save),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.items,
    required this.selected,
    required this.onToggleItem,
    required this.onToggleAll,
  });

  final String title;
  final List<PermItem> items;
  final Set<String> selected;
  final void Function(PermItem item, bool value) onToggleItem;
  final void Function(bool value) onToggleAll;

  @override
  Widget build(BuildContext context) {
    final allSelected = items.every((p) => selected.contains(p.key));
    return SectionCard(
      title: title,
      child: Column(
        children: <Widget>[
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: allSelected,
            title: Text('تحديد الكل – $title'),
            onChanged: (v) => onToggleAll(v ?? false),
          ),
          const Divider(height: 1),
          for (final p in items)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: selected.contains(p.key),
              title: Text(p.label),
              subtitle: Text(p.key),
              onChanged: (v) => onToggleItem(p, v ?? false),
            ),
        ],
      ),
    );
  }
}
