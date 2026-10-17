import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/warehouse.dart';
import '../../state/customers_controller.dart';
import '../../state/pos_controller.dart';
import '../../state/product_catalog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';

const List<String> _paymentMethods = <String>[
  'CASH',
  'CARD',
  'BANK_TRANSFER',
  'MOBILE_MONEY',
  'CHEQUE',
  'OTHER',
];

/// Point of sale: browse products, build a cart and take payment.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Warehouse> _warehouses = <Warehouse>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductCatalog>().ensureLoaded();
      context.read<CustomersController>().ensureLoaded();
      _loadWarehouses();
    });
  }

  Future<void> _loadWarehouses() async {
    try {
      final page = await context.read<Session>().api.getPage<Warehouse>(
            '/warehouses',
            query: <String, dynamic>{'page': 1, 'pageSize': 100},
            parse: Warehouse.fromJson,
          );
      if (!mounted) return;
      setState(() => _warehouses = page.items);
    } catch (_) {
      // The checkout will prompt the user if no warehouse is available.
    }
  }

  Future<void> _openCheckout() async {
    if (_warehouses.isEmpty) {
      await _loadWarehouses();
      if (!mounted) return;
      if (_warehouses.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.noWarehousesAvailable)),
        );
        return;
      }
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CheckoutSheet(warehouses: _warehouses),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<PosController>();
    final catalog = context.watch<ProductCatalog>();

    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AppSearchField(
              hintText: context.s.searchProductsHint,
              initialValue: catalog.search,
              onChanged: catalog.onSearchChanged,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildProductArea(catalog),
          ),
          _CartBar(onCheckout: cart.isEmpty ? null : _openCheckout),
        ],
      ),
    );
  }

  Widget _buildProductArea(ProductCatalog catalog) {
    if (catalog.loading && catalog.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalog.error != null && catalog.products.isEmpty) {
      return ErrorView(
        message: catalog.error!,
        onRetry: () => catalog.load(force: true),
      );
    }
    if (catalog.products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: context.s.noProducts,
        message: context.s.addProductsToStartSelling,
      );
    }
    return RefreshIndicator(
      onRefresh: () => catalog.load(force: true),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisExtent: 132,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: catalog.products.length,
        itemBuilder: (context, index) {
          final product = catalog.products[index];
          return _ProductCard(product: product);
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final dynamic product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = context.watch<PosController>();
    final inCart = cart.lines
        .any((line) => line.product.id == (product.id as String? ?? ''));

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => cart.addProduct(product),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  '${product.name}',
                  style: theme.textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${product.sku}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: MoneyText(
                      product.salePrice,
                      currencyCode: product.currencyCode,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (inCart)
                    Icon(Icons.shopping_cart, size: 16, color: theme.colorScheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.onCheckout});

  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = context.watch<PosController>();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    context.s.itemsCount(cart.itemCount),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  MoneyText(
                    cart.total,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onCheckout,
              icon: const Icon(Icons.point_of_sale),
              label: Text(context.s.checkout),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkout sheet: cart lines, customer / warehouse / method and payment.
class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({required this.warehouses});

  final List<Warehouse> warehouses;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  late String? _warehouseId;
  String? _customerId;
  late String _method;
  late final TextEditingController _paid;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final cart = context.read<PosController>();
    _warehouseId = cart.warehouseId ?? widget.warehouses.first.id;
    _customerId = cart.customerId;
    _method = cart.method;
    _paid = TextEditingController(text: Formatters.number(cart.total));
  }

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cart = context.read<PosController>();
    cart
      ..setWarehouse(_warehouseId)
      ..setCustomer(_customerId)
      ..setMethod(_method);
    final paid = double.tryParse(_paid.text.trim()) ?? 0;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _submitting = true);
    final data = await cart.submit(paidAmount: paid);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (data == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(cart.error ?? context.s.couldNotCompleteSale)),
      );
      return;
    }
    final invoice = data['invoice'];
    final number = (invoice is Map ? invoice['number'] : null)?.toString();
    final change = (data['change'] as num?) ?? 0;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          context.s.saleComplete(
            invoiceNumber: number,
            change: Formatters.money(change),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final cart = context.watch<PosController>();
    final customers = context.watch<CustomersController>();
    final theme = Theme.of(context);
    final paid = double.tryParse(_paid.text.trim()) ?? 0;
    final change = (paid - cart.total).clamp(0.0, double.infinity).toDouble();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(s.checkout, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: <Widget>[
                  SectionCard(
                    title: s.cart,
                    subtitle: s.itemsCount(cart.itemCount),
                    child: Column(
                      children: <Widget>[
                        if (cart.isEmpty)
                          Text(
                            s.cartIsEmpty,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        for (final line in cart.lines)
                          _CartLineRow(line: line),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: s.details,
                    child: Column(
                      children: <Widget>[
                        AppSelectField<String>(
                          label: s.warehouseRequired,
                          value: _warehouseId,
                          prefixIcon: Icons.warehouse_outlined,
                          options: widget.warehouses
                              .map(
                                (warehouse) => SelectOption<String>(
                                  warehouse.id,
                                  '${warehouse.code} — ${warehouse.name}',
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _warehouseId = value),
                        ),
                        const SizedBox(height: 14),
                        AppSelectField<String>(
                          label: s.customer,
                          value: _customerId,
                          hint: s.walkInCustomer,
                          prefixIcon: Icons.person_outline,
                          options: customers.items
                              .map(
                                (customer) => SelectOption<String>(
                                  customer.id,
                                  customer.name,
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _customerId = value),
                        ),
                        const SizedBox(height: 14),
                        AppSelectField<String>(
                          label: s.paymentMethod,
                          value: _method,
                          prefixIcon: Icons.payments_outlined,
                          options: _paymentMethods
                              .map(
                                (method) => SelectOption<String>(
                                  method,
                                  s.status(method),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(
                            () => _method = value ?? 'CASH',
                          ),
                        ),
                        const SizedBox(height: 14),
                        AppNumberField(
                          label: s.amountReceived,
                          controller: _paid,
                          prefixIcon: Icons.attach_money,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                children: <Widget>[
                  _SummaryRow(label: s.subtotal, amount: cart.subtotal),
                  _SummaryRow(label: s.total, amount: cart.total, emphasise: true),
                  _SummaryRow(label: s.change, amount: change),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_submitting ? s.processing : s.completeSale),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLineRow extends StatelessWidget {
  const _CartLineRow({required this.line});

  final PosCartLine line;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final cart = context.read<PosController>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(line.product.name, style: theme.textTheme.bodyLarge),
                MoneyText(
                  line.lineTotal,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.decrease,
            onPressed: () =>
                cart.setQuantity(line.product.id, line.quantity - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('${line.quantity}', style: theme.textTheme.titleMedium),
          IconButton(
            tooltip: s.increase,
            onPressed: () =>
                cart.setQuantity(line.product.id, line.quantity + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: s.remove,
            onPressed: () => cart.removeProduct(line.product.id),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.amount,
    this.emphasise = false,
  });

  final String label;
  final double amount;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        emphasise ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          MoneyText(
            amount,
            style: style?.copyWith(
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
