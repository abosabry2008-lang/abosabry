import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../models/product.dart';
import '../../state/product_catalog.dart';

/// A read-only product field that opens a searchable picker sheet.
class ProductPickerField extends StatelessWidget {
  const ProductPickerField({
    super.key,
    required this.product,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  final Product? product;
  final ValueChanged<Product> onChanged;
  final String? label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = product;
    final s = context.s;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled
          ? () async {
              final picked = await showProductPicker(context);
              if (picked != null) onChanged(picked);
            }
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label ?? s.product,
          prefixIcon: const Icon(Icons.inventory_2_outlined),
          enabled: enabled,
        ),
        child: Text(
          selected == null
              ? s.selectAProduct
              : '${selected.name} (${selected.sku})',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Opens the searchable product picker and returns the chosen product.
Future<Product?> showProductPicker(BuildContext context) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ProductPickerSheet(),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProductCatalog>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Product> _filter(List<Product> products) {
    if (_query.isEmpty) return products;
    final query = _query.toLowerCase();
    return products.where((product) {
      return product.name.toLowerCase().contains(query) ||
          product.sku.toLowerCase().contains(query) ||
          (product.barcode ?? '').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ProductCatalog>();
    final products = _filter(catalog.products);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: <Widget>[
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (value) {
                setState(() => _query = value.trim());
                catalog.onSearchChanged(value);
              },
              decoration: InputDecoration(
                hintText: context.s.searchProductsByNameSku,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            if (catalog.loading && catalog.products.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (catalog.error != null && catalog.products.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    catalog.error!,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (products.isEmpty)
              Expanded(
                child: Center(child: Text(context.s.noMatchingProducts)),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return ListTile(
                      title: Text(product.name),
                      subtitle: Text(
                        '${product.sku}'
                        '${product.barcode == null ? '' : ' · ${product.barcode}'}',
                      ),
                      trailing: Text(
                        Formatters.money(
                          product.salePrice,
                          currencyCode: product.currencyCode,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(product),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
