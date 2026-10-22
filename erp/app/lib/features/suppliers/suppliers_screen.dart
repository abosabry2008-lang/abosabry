import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/supplier.dart';
import '../../state/suppliers_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../shell/navigation.dart';
import 'supplier_form_screen.dart';
import 'supplier_statement_screen.dart';

/// Supplier list with search, create, edit and delete.
class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  Future<void> _delete(BuildContext context, Supplier supplier) async {
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.deleteSupplierQ,
      message: s.supplierWillBeRemoved(supplier.name),
      confirmLabel: s.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final controller = context.read<SuppliersController>();
    try {
      await controller.api.delete('/suppliers/${supplier.id}');
      controller.removeWhere((item) => item.id == supplier.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.supplierDeleted(supplier.name))),
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
    final controller = context.watch<SuppliersController>();
    final canManage = context.watch<Session>().can('suppliers');

    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: AppSearchField(
                    hintText: s.searchSuppliersHint,
                    initialValue: controller.search,
                    onChanged: controller.searchWith,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => controller.refresh(),
                  icon: const Icon(Icons.search),
                  label: Text(s.search),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncListView<Supplier>(
              controller: controller,
              emptyIcon: Icons.local_shipping_outlined,
              emptyTitle: s.noSuppliers,
              emptyMessage: s.addSupplierHint,
              itemBuilder: (context, supplier, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: Text(supplier.name),
                  subtitle: Text(
                    <String>[
                      if (supplier.code != null) supplier.code!,
                      if (supplier.contact != null) supplier.contact!,
                      if (supplier.email != null) supplier.email!,
                      if (supplier.phone != null) supplier.phone!,
                    ].join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          MoneyText(supplier.balance, colorNegative: true),
                          Text(
                            s.balance,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: s.accountStatement,
                        icon: const Icon(Icons.list_alt_outlined),
                        onPressed: () => openSupplierStatement(
                          context,
                          supplierId: supplier.id,
                          supplierName: supplier.name,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => pushScreen<void>(
                    context,
                    supplier.name,
                    SupplierFormScreen(supplier: supplier),
                  ),
                  onLongPress: canManage ? () => _delete(context, supplier) : null,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => pushScreen<void>(
                context,
                s.newSupplier,
                const SupplierFormScreen(),
              ),
              icon: const Icon(Icons.add),
              label: Text(s.supplier),
            )
          : null,
    );
  }
}
