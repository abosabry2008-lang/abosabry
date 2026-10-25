import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../models/product.dart';
import '../../state/categories_controller.dart';
import '../../state/products_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/page_header.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../shell/navigation.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

/// Product catalogue with search, category filter, low-stock filter and a
/// barcode lookup.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CategoriesController>().ensureLoaded();
    });
  }

  Future<void> _openBarcodeLookup() async {
    final controller = TextEditingController();
    final s = context.s;
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.barcodeLookup),
        content: AppTextField(
          label: s.barcode,
          controller: controller,
          autofocus: true,
          prefixIcon: Icons.qr_code,
          textInputAction: TextInputAction.search,
          onFieldSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(s.search),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty || !mounted) return;

    final products = context.read<ProductsController>();
    try {
      final product = await products.findByBarcode(code);
      if (!mounted) return;
      await pushScreen<void>(
        context,
        product.name,
        ProductDetailScreen(productId: product.id, initial: product),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.productNotFound)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ProductsController>();
    final categories = context.watch<CategoriesController>();
    final session = context.watch<Session>();

    return Scaffold(
      body: Column(
        children: <Widget>[
          PageHeader(
            title: s.products,
            subtitle: s.productCountLabel('${controller.total}'),
            filters: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppSearchField(
                      hintText: s.searchProductsByNameSku,
                      initialValue: controller.search,
                      onChanged: controller.searchWith,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: s.barcodeLookup,
                    onPressed: _openBarcodeLookup,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppSelectField<String>(
                      label: s.category,
                      value: controller.categoryId,
                      hint: s.allCategories,
                      options: <SelectOption<String>>[
                        SelectOption<String>('', s.allCategories),
                        ...categories.items.map(
                          (category) => SelectOption<String>(
                            category.id,
                            category.name,
                          ),
                        ),
                      ],
                      onChanged: (value) => controller.filterByCategory(
                        value == null || value.isEmpty ? null : value,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(s.lowStock),
                    selected: controller.lowStockOnly,
                    onSelected: (value) => controller.setLowStockOnly(value),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  FilterChip(
                    label: Text(s.showInactive),
                    selected: controller.showInactive,
                    onSelected: (value) {
                      controller.setShowInactive(value);
                      if (!value) controller.setShowDeleted(false);
                    },
                  ),
                  FilterChip(
                    label: Text(s.showDeleted),
                    selected: controller.showDeleted,
                    onSelected: controller.setShowDeleted,
                  ),
                ],
              ),
            ],
          ),
          if (controller.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  s.productCount(Formatters.integer(controller.total)),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            ),
          Expanded(
            child: AsyncListView<Product>(
              controller: controller,
              emptyIcon: Icons.inventory_2_outlined,
              emptyTitle: s.noProductsFound,
              emptyMessage: s.adjustFiltersOrAddProduct,
              itemBuilder: (context, product, index) => _ProductTile(
                product: product,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: session.can('products')
          ? FloatingActionButton.extended(
              onPressed: () => pushScreen<void>(
                context,
                s.newProduct,
                const ProductFormScreen(),
              ),
              icon: const Icon(Icons.add),
              label: Text(s.product),
            )
          : null,
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});

  final Product product;

  Future<void> _changeCategory(
    BuildContext context,
    String? categoryId,
  ) async {
    final api = context.read<Session>().api;
    final controller = context.read<ProductsController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await api.patchObject(
        '/products/${product.id}',
        body: <String, dynamic>{'categoryId': categoryId},
      );
      final updated = Product.fromJson(data);
      controller.replaceWhere(
        (item) => item.id == updated.id,
        (_) => updated,
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = context.watch<CategoriesController>().items;
    final canWrite = context.watch<Session>().can('products');
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => pushScreen<void>(
          context,
          product.name,
          ProductDetailScreen(productId: product.id, initial: product),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            product.name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!product.active) ...<Widget>[
                          const SizedBox(width: 8),
                          const _InactiveBadge(),
                        ],
                        if (product.isDeleted) ...<Widget>[
                          const SizedBox(width: 8),
                          const _DeletedBadge(),
                        ],
                        const Spacer(),
                        IconButton(
                          tooltip: context.s.productCard,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.print_outlined, size: 18),
                          onPressed: () => PrintService.printItemMovement(
                            context,
                            productId: product.id,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${product.sku}'
                      '${product.categoryName == null ? '' : ' · ${product.categoryName}'}'
                      ' · ${product.unit}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  MoneyText(
                    product.salePrice,
                    currencyCode: product.currencyCode,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (product.quantityOnHand != null)
                    Text(
                      product.boxesPerCarton > 0
                          ? context.s.packStock(
                              product.quantityOnHand! ~/
                                  product.boxesPerCarton,
                              product.quantityOnHand! %
                                  product.boxesPerCarton,
                            )
                          : context.s.onHandCount(
                              Formatters.integer(product.quantityOnHand),
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: product.isLowStock
                            ? theme.colorScheme.error
                            : theme.colorScheme.outline,
                      ),
                    ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: categories.any(
                          (category) => category.id == product.categoryId,
                        )
                            ? product.categoryId
                            : null,
                        isDense: true,
                        isExpanded: true,
                        icon: const Icon(Icons.category_outlined, size: 16),
                        hint: Text(context.s.category),
                        items: <DropdownMenuItem<String?>>[
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(context.s.uncategorized),
                          ),
                          for (final category in categories)
                            DropdownMenuItem<String?>(
                              value: category.id,
                              child: Text(
                                category.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: canWrite
                            ? (value) => _changeCategory(context, value)
                            : null,
                      ),
                    ),
                  ),
                  if (product.isDeleted)
                    TextButton.icon(
                      onPressed: () => context
                          .read<ProductsController>()
                          .restore(product.id),
                      icon: const Icon(Icons.restore, size: 16),
                      label: Text(context.s.restore),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InactiveBadge extends StatelessWidget {
  const _InactiveBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.s.inactive,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onErrorContainer),
      ),
    );
  }
}

class _DeletedBadge extends StatelessWidget {
  const _DeletedBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        context.s.deleted,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
    );
  }
}
