import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/warehouse.dart';
import '../../state/warehouses_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// Locations (bins / shelves) inside a single warehouse.
class LocationsScreen extends StatefulWidget {
  const LocationsScreen({
    super.key,
    required this.warehouseId,
    this.warehouseName,
  });

  final String warehouseId;
  final String? warehouseName;

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  late final LocationsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LocationsController(context.read<Session>().api);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.load(widget.warehouseId);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openForm({Location? location}) async {
    final s = context.s;
    final formKey = GlobalKey<FormState>();
    final codeController = TextEditingController(text: location?.code ?? '');
    final nameController = TextEditingController(text: location?.name ?? '');
    var active = location?.active ?? true;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(location == null ? s.newLocation : s.editLocation),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppTextField(
                  label: s.codeStar,
                  controller: codeController,
                  enabled: !saving,
                  autofocus: true,
                  prefixIcon: Icons.qr_code_2,
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? s.codeRequired : null,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: s.name,
                  controller: nameController,
                  enabled: !saving,
                  prefixIcon: Icons.label_outline,
                ),
                const SizedBox(height: 8),
                AppSwitchField(
                  label: s.active,
                  value: active,
                  enabled: !saving,
                  onChanged: (value) => setState(() => active = value),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setState(() => saving = true);
                      final api = context.read<Session>().api;
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogContext);
                      final body = <String, dynamic>{
                        'code': codeController.text.trim(),
                        'name': nameController.text.trim().isEmpty
                            ? null
                            : nameController.text.trim(),
                        'active': active,
                      };
                      try {
                        if (location == null) {
                          await api.post(
                            '/warehouses/${widget.warehouseId}/locations',
                            body: body,
                          );
                        } else {
                          await api.patch(
                            '/locations/${location.id}',
                            body: body,
                          );
                        }
                        if (!dialogContext.mounted) return;
                        navigator.pop();
                        await _controller.reload();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              location == null
                                  ? s.locationCreated
                                  : s.locationUpdated,
                            ),
                          ),
                        );
                      } on ApiException catch (error) {
                        setState(() => saving = false);
                        messenger.showSnackBar(
                          SnackBar(content: Text(error.message)),
                        );
                      }
                    },
              child: Text(saving ? s.saving : s.save),
            ),
          ],
        ),
      ),
    );

    codeController.dispose();
    nameController.dispose();
  }

  Future<void> _delete(Location location) async {
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.deleteLocationQ,
      message: s.locationWillBeRemoved(location.label),
      confirmLabel: s.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<Session>().api.delete('/locations/${location.id}');
      await _controller.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.locationDeleted)),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.loading && _controller.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_controller.error != null && _controller.items.isEmpty) {
            return ErrorView(
              message: _controller.error!,
              onRetry: _controller.reload,
            );
          }
          if (_controller.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _controller.reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  const SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.place_outlined,
                    title: s.noLocations,
                    message: s.addBinHint,
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _controller.reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _controller.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final location = _controller.items[index];
                return SectionCard(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(location.label),
                    subtitle: Text(location.active ? s.active : s.inactive),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openForm(location: location);
                        } else if (value == 'delete') {
                          _delete(location);
                        }
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
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: Text(s.locationWord),
      ),
    );
  }
}
