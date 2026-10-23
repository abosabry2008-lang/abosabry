import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../models/supplier.dart';
import '../../widgets/empty_state.dart';
import '../customers/customer_form_screen.dart';
import '../invoices/invoice_detail_screen.dart';
import '../products/product_detail_screen.dart';
import '../sales/sales_order_detail_screen.dart';
import '../shell/navigation.dart';
import '../suppliers/supplier_form_screen.dart';

/// One search box for customers, products, invoices, orders and suppliers.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> _customers = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _products = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _invoices = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _orders = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _suppliers = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final term = value.trim();
    if (term.length < 2) {
      setState(() {
        _loading = false;
        _error = null;
        _customers = <Map<String, dynamic>>[];
        _products = <Map<String, dynamic>>[];
        _invoices = <Map<String, dynamic>>[];
        _orders = <Map<String, dynamic>>[];
        _suppliers = <Map<String, dynamic>>[];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(term));
  }

  Future<List<Map<String, dynamic>>> _list(
    String path,
    String term, {
    required bool allowed,
  }) async {
    if (!allowed) return <Map<String, dynamic>>[];
    try {
      return await context.read<Session>().api.getList(
            path,
            query: <String, dynamic>{'search': term, 'pageSize': 8},
          );
    } on ApiException {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _search(String term) async {
    final session = context.read<Session>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait(<Future<List<Map<String, dynamic>>>>[
        _list('/customers', term, allowed: session.can('customers')),
        _list('/products', term, allowed: session.can('products')),
        _list('/invoices', term, allowed: session.can('invoices')),
        _list('/sales-orders', term, allowed: session.can('sales')),
        _list('/suppliers', term, allowed: session.can('suppliers')),
      ]);
      if (!mounted || _query.text.trim() != term) return;
      setState(() {
        _customers = results[0];
        _products = results[1];
        _invoices = results[2];
        _orders = results[3];
        _suppliers = results[4];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.s.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final hasQuery = _query.text.trim().length >= 2;
    final hasResults = _customers.isNotEmpty ||
        _products.isNotEmpty ||
        _invoices.isNotEmpty ||
        _orders.isNotEmpty ||
        _suppliers.isNotEmpty;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _query,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (value) {
              final term = value.trim();
              if (term.length >= 2) _search(term);
            },
            decoration: InputDecoration(
              hintText: s.searchEverythingHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: s.clear,
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _query.clear();
                        _onChanged('');
                      },
                    ),
            ),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        Expanded(
          child: !hasQuery
              ? EmptyState(
                  icon: Icons.manage_search,
                  title: s.globalSearch,
                  message: s.searchEverythingHint,
                )
              : !hasResults && !_loading
                  ? EmptyState(
                      icon: Icons.search_off,
                      title: s.noMatches,
                      message: s.searchDifferentTerm,
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      children: <Widget>[
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        _section(
                          s.customers,
                          _customers,
                          Icons.person_outline,
                          (row) => () => _openCustomer(row),
                        ),
                        _section(
                          s.products,
                          _products,
                          Icons.inventory_2_outlined,
                          (row) => () => _openProduct(row),
                        ),
                        _section(
                          s.invoices,
                          _invoices,
                          Icons.description_outlined,
                          (row) => () => _openInvoice(row),
                        ),
                        _section(
                          s.salesOrders,
                          _orders,
                          Icons.receipt_long_outlined,
                          (row) => () => _openOrder(row),
                        ),
                        _section(
                          s.suppliers,
                          _suppliers,
                          Icons.local_shipping_outlined,
                          (row) => () => _openSupplier(row),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> rows,
    IconData icon,
    VoidCallback Function(Map<String, dynamic>) onTap,
  ) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final row in rows)
              ListTile(
                leading: Icon(icon),
                title: Text(_titleFor(row)),
                subtitle: Text(_subtitleFor(row)),
                trailing: const Icon(Icons.chevron_right),
                onTap: onTap(row),
              ),
          ],
        ),
      ),
    );
  }

  String _titleFor(Map<String, dynamic> row) {
    final name = asStringOrNull(row['name']);
    if (name != null) return name;
    final number = asStringOrNull(row['number']);
    if (number != null) return number;
    return '—';
  }

  String _subtitleFor(Map<String, dynamic> row) {
    final parts = <String>[
      if (asStringOrNull(row['code']) != null) asString(row['code']),
      if (asStringOrNull(row['sku']) != null) asString(row['sku']),
      if (asStringOrNull(row['phone']) != null) asString(row['phone']),
      if (asStringOrNull(row['status']) != null)
        context.s.status(asString(row['status'])),
      if (asStringOrNull(asMap(row['customer'])['name']) != null)
        asString(asMap(row['customer'])['name']),
    ];
    return parts.join(' · ');
  }

  void _openCustomer(Map<String, dynamic> row) {
    final customer = Customer.fromJson(row);
    pushScreen<void>(
      context,
      customer.name,
      CustomerFormScreen(customer: customer),
    );
  }

  void _openProduct(Map<String, dynamic> row) {
    pushScreen<void>(
      context,
      asString(row['name']),
      ProductDetailScreen(productId: asString(row['id'])),
    );
  }

  void _openInvoice(Map<String, dynamic> row) {
    pushScreen<void>(
      context,
      asString(row['number']),
      InvoiceDetailScreen(
        invoiceId: asString(row['id']),
        initial: Invoice.fromJson(row),
      ),
    );
  }

  void _openOrder(Map<String, dynamic> row) {
    pushScreen<void>(
      context,
      asString(row['number']),
      SalesOrderDetailScreen(orderId: asString(row['id'])),
    );
  }

  void _openSupplier(Map<String, dynamic> row) {
    final supplier = Supplier.fromJson(row);
    pushScreen<void>(
      context,
      supplier.name,
      SupplierFormScreen(supplier: supplier),
    );
  }
}
