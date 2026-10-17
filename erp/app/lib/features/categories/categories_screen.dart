import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/category.dart';
import '../../state/categories_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// Category management: list, search, create, edit and delete.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  Future<void> _openForm(
    BuildContext context, {
    Category? category,
  }) async {
    final s = context.s;
    final controller = context.read<CategoriesController>();
    final nameController = TextEditingController(text: category?.name ?? '');
    final descriptionController =
        TextEditingController(text: category?.description ?? '');
    final formKey = GlobalKey<FormState>();
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(category == null ? s.newCategory : s.editCategory),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppTextField(
                  label: s.nameStar,
                  controller: nameController,
                  enabled: !saving,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? s.nameRequired
                      : null,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: s.description,
                  controller: descriptionController,
                  enabled: !saving,
                  maxLines: 2,
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
                      final body = <String, dynamic>{
                        'name': nameController.text.trim(),
                        'description': descriptionController.text.trim().isEmpty
                            ? null
                            : descriptionController.text.trim(),
                      };
                      try {
                        if (category == null) {
                          await controller.api.post('/categories', body: body);
                        } else {
                          await controller.api.patch(
                            '/categories/${category.id}',
                            body: body,
                          );
                        }
                        await controller.refresh();
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              category == null
                                  ? s.categoryCreated
                                  : s.categoryUpdated,
                            ),
                          ),
                        );
                      } on ApiException catch (error) {
                        setState(() => saving = false);
                        if (!dialogContext.mounted) return;
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

    nameController.dispose();
    descriptionController.dispose();
  }

  Future<void> _delete(BuildContext context, Category category) async {
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.deleteCategoryQ,
      message: s.categoryWillBeRemoved(category.name),
      confirmLabel: s.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final controller = context.read<CategoriesController>();
    try {
      await controller.api.delete('/categories/${category.id}');
      controller.removeWhere((item) => item.id == category.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.categoryDeleted(category.name))),
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
    final controller = context.watch<CategoriesController>();
    final canManage = context.watch<Session>().can('products');

    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AppSearchField(
              hintText: s.searchCategoriesHint,
              initialValue: controller.search,
              onChanged: controller.searchWith,
            ),
          ),
          Expanded(
            child: AsyncListView<Category>(
              controller: controller,
              emptyIcon: Icons.category_outlined,
              emptyTitle: s.noCategories,
              emptyMessage: s.createCategoryHint,
              itemBuilder: (context, category, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: Text(category.name),
                  subtitle: Text(
                    category.description?.isNotEmpty == true
                        ? category.description!
                        : s.productCount(
                            Formatters.integer(category.productCount),
                          ),
                  ),
                  trailing: canManage
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _openForm(context, category: category);
                            } else if (value == 'delete') {
                              _delete(context, category);
                            }
                          },
                          itemBuilder: (_) => <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.edit_outlined),
                                title: Text(s.edit),
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.delete_outline),
                                title: Text(s.delete),
                              ),
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
              label: Text(s.categoryWord),
            )
          : null,
    );
  }
}
