import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/cash_box.dart';
import '../../models/sales_order.dart';
import '../../models/warehouse.dart';
import '../../state/customers_controller.dart';
import '../../state/product_catalog.dart';
import '../../state/sales_orders_controller.dart';
import '../../state/salespeople_controller.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
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
  List<CashBox> _boxes = <CashBox>[];
  String? _customerId;
  String? _salespersonId;
  String? _warehouseId;
  String? _paymentCashBoxId;
  String _paymentMethod = 'CASH';
  late final TextEditingController _paidAmount = TextEditingController(
    text: (widget.order?.paidAmount ?? 0).toString(),
  );
  DateTime _orderDate = DateTime.now();
  bool _saving = false;
  bool _linesDirty = false;
  bool _showProfit = false;
  bool _showPayment = false;

  bool get _editing => widget.order != null;

  /// The payment is posted when the invoice is issued, so it can no longer be
  /// changed here once the order has been executed.
  bool get _paymentLocked {
    final status = widget.order?.status;
    return status == 'FULFILLED' || status == 'PARTIALLY_FULFILLED';
  }

  @override
  void initState() {
    super.initState();
    final order = widget.order;
    if (order != null) {
      _customerId = order.customerId;
      _warehouseId = order.warehouseId;
      _orderDate = order.orderDate ?? DateTime.now();
      _paymentCashBoxId = order.paymentCashBoxId;
      _paymentMethod = order.paymentMethod;
      _showPayment = order.paidAmount > 0;
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.read<CustomersController>().ensureCatalogLoaded();
      context.read<SalespeopleController>().ensureLoaded();
      await _loadWarehouses();
      await _loadBoxes();
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
    _paidAmount.dispose();
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

  Future<void> _loadBoxes() async {
    try {
      final rows = await context.read<Session>().api.getList('/treasury/boxes');
      if (!mounted) return;
      final boxes = rows
          .map(CashBox.fromJson)
          .where((box) => box.active)
          .toList();
      setState(() {
        _boxes = boxes;
        _paymentCashBoxId ??= boxes.isEmpty
            ? null
            : boxes
                .where((box) => box.isDefault)
                .map((box) => box.id)
                .firstOrNull ??
                boxes.first.id;
      });
    } on ApiException {
      // Payment is optional; the default box is used server-side.
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
    final orderTotal = validLines.fold<double>(
      0,
      (sum, line) => sum + line.lineTotal,
    );
    final paid = double.tryParse(_paidAmount.text.trim()) ?? 0;
    if (paid < 0 || paid > orderTotal + 0.009) {
      _snack(context.s.paidAmountInvalid);
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
            'paidAmount': paid,
            'paymentCashBoxId': _paymentCashBoxId,
            'paymentMethod': _paymentMethod,
            'orderDate': _orderDate.toUtc().toIso8601String(),
            'lines': _linesJson(validLines),
          },
        );
        await controller.refresh();
        if (!mounted) return;
        _snack(context.s.salesOrderCreated);
      } else {
        final body = <String, dynamic>{
          'customerId': _customerId,
          'paidAmount': paid,
          'paymentCashBoxId': _paymentCashBoxId,
          'paymentMethod': _paymentMethod,
          'orderDate': _orderDate.toUtc().toIso8601String(),
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
    final theme = Theme.of(context);
    final session = context.watch<Session>();
    final customers = context.watch<CustomersController>();
    final salespeople = context.watch<SalespeopleController>();

    final filteredCustomers = customers.catalog
        .where((c) => _salespersonId == null || c.salespersonId == _salespersonId)
        .toList();
    final selectedCustomer = _customerId == null
        ? null
        : customers.catalog
            .where((customer) => customer.id == _customerId)
            .firstOrNull;

    return Scaffold(
      body: Form(
        key: _formKey,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    children: <Widget>[
                      SectionCard(
                        title: s.orderData,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 620;
                            final customerField = SearchablePickerField(
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
                              onChanged: (value) =>
                                  setState(() => _customerId = value),
                            );
                            final dateField = AppDateField(
                              label: s.orderDate,
                              value: _orderDate,
                              enabled: !_saving,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _orderDate = value);
                                }
                              },
                            );
                            final salespersonField = SearchablePickerField(
                              label: s.salesperson,
                              value: _salespersonId,
                              hint: s.chooseSalesperson,
                              enabled: !_saving,
                              prefixIcon: Icons.badge_outlined,
                              searchHint: s.searchHint,
                              clearable: true,
                              options: salespeople.salespeople
                                  .map(
                                    (p) => PickerOption(
                                      value: p.id,
                                      label: p.name,
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() {
                                _salespersonId =
                                    (value == null || value.isEmpty)
                                        ? null
                                        : value;
                                if (_salespersonId != null &&
                                    _customerId != null) {
                                  final cust = customers.catalog
                                      .where((c) => c.id == _customerId)
                                      .firstOrNull;
                                  if (cust == null ||
                                      cust.salespersonId != _salespersonId) {
                                    _customerId = null;
                                  }
                                }
                              }),
                            );
                            final warehouseField = AppSelectField<String>(
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
                              onChanged: (value) =>
                                  setState(() => _warehouseId = value),
                              validator: (value) =>
                                  value == null ? s.warehouseIsRequired : null,
                            );

                            final fields = wide
                                ? Column(
                                    children: <Widget>[
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Expanded(
                                            flex: 2,
                                            child: customerField,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(child: dateField),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          if (!session.isSalesperson) ...<Widget>[
                                            Expanded(
                                              child: salespersonField,
                                            ),
                                            const SizedBox(width: 10),
                                          ],
                                          Expanded(child: warehouseField),
                                        ],
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: <Widget>[
                                      customerField,
                                      const SizedBox(height: 10),
                                      dateField,
                                      if (!session.isSalesperson) ...<Widget>[
                                        const SizedBox(height: 10),
                                        salespersonField,
                                      ],
                                      const SizedBox(height: 10),
                                      warehouseField,
                                    ],
                                  );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                fields,
                                if (selectedCustomer != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          Icons.account_balance_wallet_outlined,
                                          size: 14,
                                          color:
                                              theme.colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${s.previousBalanceLabel}: ',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        MoneyText(
                                          selectedCustomer.balance,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const Divider(height: 18),
                                _PaymentSection(
                                  expanded: _showPayment,
                                  locked: _paymentLocked,
                                  paidAmount: _paidAmount.text,
                                  cashBoxField: AppSelectField<String?>(
                                    label: s.cashBox,
                                    value: _paymentCashBoxId,
                                    hint: s.chooseBox,
                                    enabled: !_paymentLocked,
                                    prefixIcon: Icons
                                        .account_balance_wallet_outlined,
                                    options: _boxes
                                        .map(
                                          (box) => SelectOption<String?>(
                                            box.id,
                                            box.name,
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) => setState(
                                      () => _paymentCashBoxId = value,
                                    ),
                                  ),
                                  paidField: AppNumberField(
                                    label: s.paid,
                                    controller: _paidAmount,
                                    enabled: !_paymentLocked,
                                    prefixIcon: Icons.payments_outlined,
                                    onChanged: (_) => setState(() {}),
                                  ),
                                  wide: wide,
                                  onToggle: () => setState(
                                    () => _showPayment = !_showPayment,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SectionCard(
                        title: s.lines,
                        subtitle: s.lineCount(
                          _lines.where((line) => line.isValid).length,
                        ),
                        trailing: session.isAdmin
                            ? TextButton.icon(
                                onPressed: () =>
                                    setState(() => _showProfit = !_showProfit),
                                icon: Icon(
                                  _showProfit
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                label: Text(
                                  _showProfit ? s.hideProfit : s.showProfit,
                                ),
                              )
                            : null,
                        child: OrderLinesEditor(
                          lines: _lines,
                          enabled: !_saving,
                          showDiscount: true,
                          preferSalePrice: true,
                          enforceSalePriceFloor: true,
                          showHistoryHint: false,
                          customerId: _customerId,
                          showProfit: session.isAdmin && _showProfit,
                          onChanged: () => setState(() => _linesDirty = true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _OrderFooter(
              total: _lines
                  .where((line) => line.isValid)
                  .fold<double>(0, (sum, line) => sum + line.lineTotal),
              lineCount: _lines.where((line) => line.isValid).length,
              saving: _saving,
              saveLabel: _editing ? s.save : s.createOrder,
              onCancel: () =>
                  _saving ? null : Navigator.of(context).pop(false),
              onSave: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsible payment block: cash box + paid amount are optional when the
/// order is created, so they stay out of the way until needed.
class _PaymentSection extends StatelessWidget {
  const _PaymentSection({
    required this.expanded,
    required this.locked,
    required this.paidAmount,
    required this.cashBoxField,
    required this.paidField,
    required this.wide,
    required this.onToggle,
  });

  final bool expanded;
  final bool locked;
  final String paidAmount;
  final Widget cashBoxField;
  final Widget paidField;
  final bool wide;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final paid = double.tryParse(paidAmount.trim()) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.payments_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  s.paymentOptional,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (paid > 0) ...<Widget>[
                  const SizedBox(width: 8),
                  MoneyText(
                    paid,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const Spacer(),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...<Widget>[
          const SizedBox(height: 6),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: cashBoxField),
                const SizedBox(width: 10),
                Expanded(child: paidField),
              ],
            )
          else ...<Widget>[
            cashBoxField,
            const SizedBox(height: 10),
            paidField,
          ],
          if (locked) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              s.paymentLockedHint,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ],
    );
  }
}

/// Sticky total + actions bar for the order form.
class _OrderFooter extends StatelessWidget {
  const _OrderFooter({
    required this.total,
    required this.lineCount,
    required this.saving,
    required this.saveLabel,
    required this.onCancel,
    required this.onSave,
  });

  final double total;
  final int lineCount;
  final bool saving;
  final String saveLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
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
                    '${s.total} · ${s.lineCount(lineCount)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  MoneyText(
                    total,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: onCancel,
              child: Text(s.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(saving ? s.saving : saveLabel),
            ),
          ],
        ),
      ),
    );
  }
}
