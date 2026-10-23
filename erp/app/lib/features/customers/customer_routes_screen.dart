import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../state/salespeople_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// Sales routes (خطوط السير). Assigning a route to a representative moves all
/// customers on that route to that representative automatically.
class CustomerRoutesScreen extends StatefulWidget {
  const CustomerRoutesScreen({super.key});

  @override
  State<CustomerRoutesScreen> createState() => _CustomerRoutesScreenState();
}

class _CustomerRoutesScreenState extends State<CustomerRoutesScreen> {
  List<Map<String, dynamic>> _routes = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalespeopleController>().ensureLoaded();
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await context
          .read<Session>()
          .api
          .getList('/customer-routes', query: <String, dynamic>{'pageSize': 100});
      if (!mounted) return;
      setState(() => _routes = rows);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? route]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RouteDialog(route: route),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> route) async {
    final confirmed = await confirmDialog(
      context,
      title: context.s.delete,
      message: asString(route['name']),
      confirmLabel: context.s.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<Session>().api.delete('/customer-routes/${asString(route['id'])}');
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_loading && _routes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _routes.isEmpty) {
      return Center(
        child: TextButton(onPressed: _load, child: Text(_error!)),
      );
    }
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          SectionCard(
            title: s.customerRoutes,
            subtitle: s.customerRoutesHint,
            child: Column(
              children: <Widget>[
                if (_routes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(s.noDataForFilters),
                  )
                else
                  for (final route in _routes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.route_outlined),
                      title: Text(asString(route['name'])),
                      subtitle: Text(
                        <String>[
                          if (asStringOrNull(route['code']) != null)
                            asString(route['code']),
                          '${s.salesperson}: ${asString(asMap(route['salesperson'])['name'], fallback: s.unassigned)}',
                          '${s.customers}: ${asInt(asMap(route['_count'])['customers'])}',
                        ].join(' · '),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') _edit(route);
                          if (value == 'delete') _delete(route);
                        },
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: Text(s.edit),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text(s.delete),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(s.customerRoute),
      ),
    );
  }
}

class _RouteDialog extends StatefulWidget {
  const _RouteDialog({this.route});

  final Map<String, dynamic>? route;

  @override
  State<_RouteDialog> createState() => _RouteDialogState();
}

class _RouteDialogState extends State<_RouteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: asString(widget.route?['name']));
  late final TextEditingController _code =
      TextEditingController(text: asString(widget.route?['code']));
  late String? _salespersonId =
      asStringOrNull(widget.route?['salespersonId']);
  late bool _active = asBool(widget.route?['active'], fallback: true);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
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
      'code': _code.text.trim().isEmpty ? null : _code.text.trim(),
      'salespersonId': _salespersonId,
      'active': _active,
    };
    try {
      final id = asStringOrNull(widget.route?['id']);
      if (id == null) {
        await api.postObject('/customer-routes', body: body);
      } else {
        await api.patchObject('/customer-routes/$id', body: body);
      }
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
    final salespeople = context.watch<SalespeopleController>().salespeople;
    return AlertDialog(
      title: Text(widget.route == null ? s.customerRoute : s.edit),
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
              AppTextField(label: s.code, controller: _code),
              const SizedBox(height: 12),
              AppSelectField<String?>(
                label: s.salesperson,
                value: _salespersonId,
                prefixIcon: Icons.support_agent_outlined,
                options: <SelectOption<String?>>[
                  SelectOption<String?>(null, s.unassigned),
                  for (final person in salespeople)
                    SelectOption<String?>(person.id, person.name),
                ],
                onChanged: (value) => setState(() => _salespersonId = value),
              ),
              const SizedBox(height: 8),
              AppSwitchField(
                label: s.active,
                value: _active,
                onChanged: (value) => setState(() => _active = value),
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
          child: Text(_saving ? s.saving : s.save),
        ),
      ],
    );
  }
}
