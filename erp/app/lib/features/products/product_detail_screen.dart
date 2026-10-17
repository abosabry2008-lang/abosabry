import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/product.dart';
import '../../state/products_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_view.dart';
import '../../widgets/section_card.dart';
import 'product_form_screen.dart';

/// Read-only product view with edit / delete actions.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId, this.initial});

  final String productId;
  final Product? initial;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Product? _product;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _product = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _product == null;
      _error = null;
    });
    try {
      final data = await context
          .read<ProductsController>()
          .api
          .getObject('/products/${widget.productId}');
      if (!mounted) return;
      setState(() => _product = Product.fromJson(data));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final product = _product;
    if (product == null) return;
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.deleteProductQ,
      message: s.productWillBeRemoved(product.name),
      confirmLabel: s.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final controller = context.read<ProductsController>();
    try {
      await controller.api.delete('/products/${product.id}');
      controller.removeWhere((item) => item.id == product.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.productDeleted(product.name))),
      );
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_loading && _product == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_product == null) {
      return Scaffold(
        body:
            ErrorView(message: _error ?? s.productNotFound, onRetry: _load),
      );
    }

    final product = _product!;
    final session = context.watch<Session>();
    final theme = Theme.of(context);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: product.name,
            subtitle: s.skuLabel(product.sku),
            trailing: !product.active
                ? Chip(
                    label: Text(s.inactive),
                    backgroundColor: theme.colorScheme.errorContainer,
                  )
                : null,
            child: Column(
              children: <Widget>[
                _DetailRow(label: s.barcode, value: product.barcode ?? '—'),
                _DetailRow(
                  label: s.category,
                  value: product.categoryName ?? '—',
                ),
                _DetailRow(label: s.unit, value: product.unit),
                _DetailRow(
                  label: s.costPrice,
                  value: Formatters.money(
                    product.costPrice,
                    currencyCode: product.currencyCode,
                  ),
                ),
                _DetailRow(
                  label: s.salePrice,
                  value: Formatters.money(
                    product.salePrice,
                    currencyCode: product.currencyCode,
                  ),
                ),
                _DetailRow(
                  label: s.taxRate,
                  value: Formatters.percent(product.taxRate),
                ),
                _DetailRow(
                  label: s.reorderLevel,
                  value: Formatters.integer(product.reorderLevel),
                ),
                _DetailRow(
                  label: s.onHand,
                  value: product.quantityOnHand == null
                      ? '—'
                      : Formatters.integer(product.quantityOnHand),
                ),
                _DetailRow(
                  label: s.trackInventory,
                  value: product.trackInventory ? s.yes : s.no,
                ),
                if (product.description != null)
                  _DetailRow(label: s.description, value: product.description!),
              ],
            ),
          ),
          if (session.can('products')) ...<Widget>[
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      final saved = await Navigator.of(context).push<bool>(
                        MaterialPageRoute<bool>(
                          builder: (_) => ProductFormScreen(product: product),
                        ),
                      );
                      if (saved == true) _load();
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(s.edit),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(s.delete),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
