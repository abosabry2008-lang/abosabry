import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/sales_order.dart';
import '../../models/warehouse.dart';
import '../../state/customers_controller.dart';
import '../../state/product_catalog.dart';
import '../../state/sales_orders_controller.dart';
import '../../state/salespeople_controller.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/order_lines_editor.dart';
import '../../widgets/section_card.dart';
import '../../widgets/searchable_picker_field.dart';

/// Create/edit form for a sales order.
///
/// Pass [order] to edit it. Editing a fulfilled order is reserved for admins;
/// the API returns the fulfilled stock and re-applies the new lines.
class SalesOrderFormScreen extends StatefulWidget {
  const SalesOrderFormScreen({super.key, this.order});

  /// The order being edited, or `null` when creating a new one.
  final SalesOrder? order;

  @override
  State<SalesOrderFormScreen> createState() => _SalesOrderFormScreenState();
}

class _SalesOrderFormScreenState extends State<SalesOrderFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final List<OrderLineDraft> _lines = <OrderLineDraft>[];

  List<Warehouse> _warehouses = <Warehouse>[];
  String? _customerId;
  String? _salespersonId;
  String? _warehouseId;
  final TextEditingController _notes = TextEditingController();
  bool _saving = false;
  bool _linesDirty = false;

  bool get _editing => widget.order != null;

  @override
  void initState() {
    super.initState();
    final order = widget.order;
    if (order != null) {
      _customerId = order.customerId;
      _warehouseId = order.warehouseId;
      _notes.text = order.notes ?? '';
      for (final line in order.lines) {
        _lines.add(
          OrderLineDraft(
            quantity: line.quantity.toDouble(),
            price: line.unitPrice,
            discount: line.discount,
            taxRate: line.taxRate,
          ),
        );
      }
    }
    if (_lines.isEmpty) _lines.add(OrderLineDraft());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.read<CustomersController>().ensureCatalogLoaded();
      context.read<SalespeopleController>().ensureLoaded();
      await _loadWarehouses();
      if (!mounted) return;
      // Resolve the products of an edited order so its lines stay valid.
      final catalog = context.read<ProductCatalog>();
      await catalog.ensureLoaded();
      if (!mounted) return;
      setState(() {
        final order = widget.order;
        if (order == null) return;
        for (var i = 0; i < _lines.length && i < order.lines.length; i++) {
          _lines[i].product ??= catalog.byId(order.lines[i].productId);
        }
      });
    });
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadWarehouses() async {
    try {
      final page = await context.read<Session>().api.getPage<Warehouse>(
            '/warehouses',
            query: <String, dynamic>{'page': 1, 'pageSize': 100},
            parse: Warehouse.fromJson,
          );
      if (!mounted) return;
      setState(() {
        _warehouses = page.items;
        _warehouseId ??= page.items.isEmpty ? null : page.items.first.id;
        // Keep an edited order's warehouse if it is still selectable.
        if (_warehouseId != null &&
            !page.items.any((warehouse) => warehouse.id == _warehouseId)) {
          _warehouseId = page.items.isEmpty ? null : page.items.first.id;
        }
      });
    } catch (_) {
      // Leave the dropdown empty; validation will block submission.
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_warehouseId == null) {
      _snack(context.s.selectAWarehouseShort);
      return;
    }
    final validLines = _lines.where((line) => line.isValid).toList();
    if (validLines.isEmpty) {
      _snack(context.s.addAtLeastOneCompleteLine);
      return;
    }
    // لا يُسمح بالبيع بسعر أقل من التكلفة.
    for (final line in validLines) {
      if (line.priceBelowCost) {
        _snack(context.s.priceBelowCost(line.product!.name));
        return;
      }
    }

    final order = widget.order;
    if (order != null) {
      final fulfilled = order.lines.any((line) => line.fulfilledQty > 0);
      // Editing quantities of an order that already shipped needs admin rights.
      if (fulfilled && _linesDirty && !context.read<Session>().can('sales.cancel')) {
        _snack(context.s.onlyAdminEditsFulfilled);
        return;
      }
    }

    setState(() => _saving = true);
    final controller = context.read<SalesOrdersController>();
    try {
      if (order == null) {
        await controller.api.post(
          '/sales-orders',
          body: <String, dynamic>{
            'customerId': _customerId,
            'warehouseId': _warehouseId,
            'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            'lines': _linesJson(validLines),
          },
        );
        await controller.refresh();
        if (!mounted) return;
        _snack(context.s.salesOrderCreated);
      } else {
        final body = <String, dynamic>{
          'customerId': _customerId,
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        };
        if (_linesDirty) body['lines'] = _linesJson(validLines);
        await controller.api.patchObject('/sales-orders/${order.id}', body: body);
        await controller.refresh();
        if (!mounted) return;
        _snack(context.s.salesOrderUpdated);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      _snack(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Map<String, dynamic>> _linesJson(List<OrderLineDraft> lines) => lines
      .map((line) => line.toJson())
      .toList();

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final customers = context.watch<CustomersController>();
    final salespeople = context.watch<SalespeopleController>();

    final filteredCustomers = customers.catalog
        .where((c) => _salespersonId == null || c.salespersonId == _salespersonId)
        .toList();

    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: s.orderDetails,
              child: Column(
                children: <Widget>[
                  SearchablePickerField(
                    label: s.salesperson,
                    value: _salespersonId,
                    hint: s.chooseSalesperson,
                    enabled: !_saving,
                    prefixIcon: Icons.badge_outlined,
                    searchHint: s.searchHint,
                    clearable: true,
                    options: salespeople.salespeople
                        .map((p) => PickerOption(value: p.id, label: p.name))
                        .toList(),
                    onChanged: (value) => setState(() {
                      _salespersonId =
                          (value == null || value.isEmpty) ? null : value;
                      // If current customer doesn't belong to selected salesperson, clear it
                      if (_salespersonId != null && _customerId != null) {
                        final cust = customers.catalog
                            .where((c) => c.id == _customerId)
                            .firstOrNull;
                        if (cust == null || cust.salespersonId != _salespersonId) {
                          _customerId = null;
                        }
                      }
                    }),
                  ),
                  const SizedBox(height: 14),
                  SearchablePickerField(
                    label: s.customer,
                    value: _customerId,
                    enabled: !_saving,
                    hint: s.walkInCustomer,
                    prefixIcon: Icons.person_outline,
                    searchHint: s.searchCustomersHint,
                    clearable: true,
                    options: filteredCustomers
                        .map(
                          (customer) => customerPickerOption(
                            id: customer.id,
                            name: customer.name,
                            code: customer.code,
                            balance: customer.balance,
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _customerId = value),
                  ),
                  const SizedBox(height: 14),
                  AppSelectField<String>(
                    label: s.warehouseRequired,
                    value: _warehouseId,
                    enabled: !_saving,
                    prefixIcon: Icons.warehouse_outlined,
                    options: _warehouses
                        .map(
                          (warehouse) => SelectOption<String>(
                            warehouse.id,
                            '${warehouse.code} — ${warehouse.name}',
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _warehouseId = value),
                    validator: (value) =>
                        value == null ? s.warehouseIsRequired : null,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.notes,
                    controller: _notes,
                    enabled: !_saving,
                    maxLines: 2,
                    prefixIcon: Icons.notes_outlined,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: s.lines,
              subtitle: s.productsToSell,
              child: OrderLinesEditor(
                lines: _lines,
                enabled: !_saving,
                showDiscount: true,
                preferSalePrice: true,
                enforceSalePriceFloor: true,
                onChanged: () => setState(() => _linesDirty = true),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(false),
                    child: Text(s.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _saving
                          ? s.saving
                          : _editing
                              ? s.save
                              : s.createOrder,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
