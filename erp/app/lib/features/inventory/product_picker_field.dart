import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
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
  bool _creating = false;

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

  /// Opens the inline "new product" dialog and returns the created product
  /// (or null when cancelled). The catalogue is refreshed so the new product
  /// appears in the list.
  Future<Product?> _createProduct() async {
    final session = context.read<Session>();
    final created = await showDialog<Product>(
      context: context,
      builder: (_) => _QuickProductDialog(session: session),
    );
    if (created != null && mounted) {
      await context.read<ProductCatalog>().load(force: true);
    }
    return created;
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ProductCatalog>();
    final products = _filter(catalog.products);
    final canCreate = context.read<Session>().can('products');
    final theme = Theme.of(context);
    final s = context.s;

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
            const SizedBox(height: 8),
            if (canCreate)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _creating
                      ? null
                      : () async {
                          setState(() => _creating = true);
                          final product = await _createProduct();
                          if (!mounted) return;
                          setState(() => _creating = false);
                          if (product != null && context.mounted) {
                            Navigator.of(context).pop(product);
                          }
                        },
                  icon: _creating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(s.quickAddProduct),
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
            if (canCreate && products.isEmpty && !catalog.loading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  s.quickAddProductHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact dialog to create a product without leaving the order screen.
class _QuickProductDialog extends StatefulWidget {
  const _QuickProductDialog({required this.session});

  final Session session;

  @override
  State<_QuickProductDialog> createState() => _QuickProductDialogState();
}

class _QuickProductDialogState extends State<_QuickProductDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _sku = TextEditingController();
  final TextEditingController _unit = TextEditingController(text: 'pc');
  final TextEditingController _costPrice = TextEditingController();
  final TextEditingController _salePrice = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _unit.dispose();
    _costPrice.dispose();
    _salePrice.dispose();
    super.dispose();
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await widget.session.api.postObject(
        '/products',
        body: <String, dynamic>{
          'name': _name.text.trim(),
          'sku': _sku.text.trim(),
          'unit': _unit.text.trim().isEmpty ? 'pc' : _unit.text.trim(),
          'costPrice': _number(_costPrice),
          'salePrice': _number(_salePrice),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(Product.fromJson(data));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AlertDialog(
      title: Text(s.quickAddProduct),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: s.nameStar),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? s.nameRequired
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sku,
                  enabled: !_saving,
                  decoration: InputDecoration(labelText: s.skuStar),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? s.skuRequired
                          : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _costPrice,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: s.costPrice,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _salePrice,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: s.salePrice,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(s.save),
        ),
      ],
    );
  }
}
