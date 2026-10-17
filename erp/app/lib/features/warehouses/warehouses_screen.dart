import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/warehouse.dart';
import '../../state/warehouses_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import '../shell/navigation.dart';
import 'locations_screen.dart';

/// Warehouse management: list, create, edit, delete and drill into locations.
class WarehousesScreen extends StatelessWidget {
  const WarehousesScreen({super.key});

  Future<void> _openForm(BuildContext context, {Warehouse? warehouse}) async {
    final s = context.s;
    final formKey = GlobalKey<FormState>();
    final codeController = TextEditingController(text: warehouse?.code ?? '');
    final nameController = TextEditingController(text: warehouse?.name ?? '');
    final addressController =
        TextEditingController(text: warehouse?.address ?? '');
    final phoneController = TextEditingController(text: warehouse?.phone ?? '');
    var active = warehouse?.active ?? true;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(warehouse == null ? s.newWarehouse : s.editWarehouse),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppTextField(
                    label: s.codeStar,
                    controller: codeController,
                    enabled: !saving,
                    autofocus: true,
                    prefixIcon: Icons.tag,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? s.codeRequired
                        : null,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.nameStar,
                    controller: nameController,
                    enabled: !saving,
                    prefixIcon: Icons.store_mall_directory_outlined,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? s.nameRequired
                        : null,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.address,
                    controller: addressController,
                    enabled: !saving,
                    maxLines: 2,
                    prefixIcon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.phone,
                    controller: phoneController,
                    enabled: !saving,
                    prefixIcon: Icons.phone_outlined,
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
                      final controller = context.read<WarehousesController>();
                      final body = <String, dynamic>{
                        'code': codeController.text.trim(),
                        'name': nameController.text.trim(),
                        'address': addressController.text.trim().isEmpty
                            ? null
                            : addressController.text.trim(),
                        'phone': phoneController.text.trim().isEmpty
                            ? null
                            : phoneController.text.trim(),
                        'active': active,
                      };
                      try {
                        if (warehouse == null) {
                          await controller.api
                              .post('/warehouses', body: body);
                        } else {
                          await controller.api.patch(
                            '/warehouses/${warehouse.id}',
                            body: body,
                          );
                        }
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              warehouse == null
                                  ? s.warehouseCreated
                                  : s.warehouseUpdated,
                            ),
                          ),
                        );
                      } on ApiException catch (error) {
                        setState(() => saving = false);
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
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
    addressController.dispose();
    phoneController.dispose();
  }

  Future<void> _delete(BuildContext context, Warehouse warehouse) async {
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.deleteWarehouseQ,
      message: s.warehouseAndLocationsWillBeRemoved(warehouse.name),
      confirmLabel: s.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final controller = context.read<WarehousesController>();
    try {
      await controller.api.delete('/warehouses/${warehouse.id}');
      controller.removeWhere((item) => item.id == warehouse.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.warehouseDeleted(warehouse.name))),
      );
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<WarehousesController>();
    final canManage = context.watch<Session>().can('warehouses');

    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AppSearchField(
              hintText: s.searchWarehousesHint,
              initialValue: controller.search,
              onChanged: controller.searchWith,
            ),
          ),
          Expanded(
            child: AsyncListView<Warehouse>(
              controller: controller,
              emptyIcon: Icons.store_mall_directory_outlined,
              emptyTitle: s.noWarehouses,
              emptyMessage: s.createWarehouseHint,
              itemBuilder: (context, warehouse, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: const Icon(Icons.store_mall_directory_outlined),
                  title: Text('${warehouse.code} — ${warehouse.name}'),
                  subtitle: Text(
                    warehouse.address ??
                        '${s.locationCount('${warehouse.locationCount}')}'
                            '${warehouse.active ? '' : ' · ${s.inactive}'}',
                  ),
                  onTap: () => pushScreen<void>(
                    context,
                    warehouse.name,
                    LocationsScreen(
                      warehouseId: warehouse.id,
                      warehouseName: warehouse.name,
                    ),
                  ),
                  trailing: canManage
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _openForm(context, warehouse: warehouse);
                            } else if (value == 'delete') {
                              _delete(context, warehouse);
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
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add),
              label: Text(s.warehouseWord),
            )
          : null,
    );
  }
}
