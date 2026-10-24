import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/supplier.dart';
import '../../models/warehouse.dart';
import '../../state/customers_controller.dart';
import '../../state/opening_balances_controller.dart';
import '../../state/suppliers_controller.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/searchable_picker_field.dart';
import '../../widgets/section_card.dart';
import '../inventory/product_picker_field.dart';

/// One customer debt line of the opening-balance form.
class _CustomerLine {
  _CustomerLine() : amount = TextEditingController();
  String? customerId;
  final TextEditingController amount;

  double get value => double.tryParse(amount.text.trim()) ?? 0;
  bool get isEmpty => customerId == null && value == 0;
  void dispose() => amount.dispose();
}

/// One supplier debt line of the opening-balance form.
class _SupplierLine {
  _SupplierLine() : amount = TextEditingController();
  String? supplierId;
  final TextEditingController amount;

  double get value => double.tryParse(amount.text.trim()) ?? 0;
  bool get isEmpty => supplierId == null && value == 0;
  void dispose() => amount.dispose();
}

/// One opening-stock line of the opening-balance form.
class _InventoryLine {
  _InventoryLine()
      : quantity = TextEditingController(text: '1'),
        unitCost = TextEditingController();
  Product? product;
  final TextEditingController quantity;
  final TextEditingController unitCost;

  int get qty => double.tryParse(quantity.text.trim())?.round() ?? 0;
  double get cost => double.tryParse(unitCost.text.trim()) ?? 0;
  double get value => qty * cost;
  bool get isValid => product != null && qty > 0;

  void dispose() {
    quantity.dispose();
    unitCost.dispose();
  }
}

/// Admin form that posts a single capital opening entry (مديونية سابقة) for
/// customer debts, supplier debts and opening stock (`POST /opening-balances`).
class OpeningBalanceFormScreen extends StatefulWidget {
  const OpeningBalanceFormScreen({super.key});

  @override
  State<OpeningBalanceFormScreen> createState() =>
      _OpeningBalanceFormScreenState();
}

class _OpeningBalanceFormScreenState extends State<OpeningBalanceFormScreen> {
  final List<_CustomerLine> _customers = <_CustomerLine>[_CustomerLine()];
  final List<_SupplierLine> _suppliers = <_SupplierLine>[_SupplierLine()];
  final List<_InventoryLine> _inventory = <_InventoryLine>[_InventoryLine()];
  final TextEditingController _note = TextEditingController();

  List<Warehouse> _warehouses = <Warehouse>[];
  String? _warehouseId;
  DateTime _asOfDate = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CustomersController>().ensureCatalogLoaded();
      context.read<SuppliersController>().ensureCatalogLoaded();
      _loadWarehouses();
    });
  }

  @override
  void dispose() {
    for (final line in _customers) {
      line.dispose();
    }
    for (final line in _suppliers) {
      line.dispose();
    }
    for (final line in _inventory) {
      line.dispose();
    }
    _note.dispose();
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
      });
    } catch (_) {
      // Leave the dropdown empty; validation blocks submission.
    }
  }

  double get _customerTotal =>
      _customers.fold<double>(0, (sum, line) => sum + line.value);
  double get _supplierTotal =>
      _suppliers.fold<double>(0, (sum, line) => sum + line.value);
  double get _inventoryTotal =>
      _inventory.fold<double>(0, (sum, line) => sum + line.value);
  double get _capital => _customerTotal + _inventoryTotal - _supplierTotal;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final s = context.s;
    final validCustomers =
        _customers.where((line) => line.customerId != null && line.value > 0);
    final validSuppliers =
        _suppliers.where((line) => line.supplierId != null && line.value > 0);
    final validInventory = _inventory.where((line) => line.isValid);

    if (validCustomers.isEmpty &&
        validSuppliers.isEmpty &&
        validInventory.isEmpty) {
      _snack(s.emptyOpeningBalance);
      return;
    }
    if (validInventory.isNotEmpty && _warehouseId == null) {
      _snack(s.needWarehouse);
      return;
    }

    setState(() => _saving = true);
    final controller = context.read<OpeningBalancesController>();
    final navigator = Navigator.of(context);
    try {
      final body = <String, dynamic>{
        'asOfDate': _asOfDate.toUtc().toIso8601String(),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'customers': validCustomers
            .map((line) => <String, dynamic>{
                  'customerId': line.customerId,
                  'amount': line.value,
                })
            .toList(),
        'suppliers': validSuppliers
            .map((line) => <String, dynamic>{
                  'supplierId': line.supplierId,
                  'amount': line.value,
                })
            .toList(),
        'inventory': validInventory
            .map((line) => <String, dynamic>{
                  'warehouseId': _warehouseId,
                  'productId': line.product!.id,
                  'quantity': line.qty,
                  'unitCost': line.cost,
                })
            .toList(),
      };
      await controller.api.post('/opening-balances', body: body);
      await controller.refresh();
      if (!mounted) return;
      _snack(s.openingSaved);
      navigator.pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      _snack(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final customers = context.watch<CustomersController>();
    final suppliers = context.watch<SuppliersController>();

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: s.newOpeningBalance,
            subtitle: s.openingBalancesHint,
            child: Column(
              children: <Widget>[
                AppDateField(
                  label: s.asOfDate,
                  value: _asOfDate,
                  enabled: !_saving,
                  onChanged: (value) =>
                      setState(() => _asOfDate = value ?? _asOfDate),
                ),
                const SizedBox(height: 14),
                if (_warehouses.isNotEmpty)
                  AppSelectField<String>(
                    label: s.warehouseWord,
                    value: _warehouseId,
                    enabled: !_saving,
                    prefixIcon: Icons.warehouse_outlined,
                    options: <SelectOption<String>>[
                      for (final warehouse in _warehouses)
                        SelectOption<String>(warehouse.id, warehouse.name),
                    ],
                    onChanged: (value) =>
                        setState(() => _warehouseId = value),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _CustomerSection(
            lines: _customers,
            customers: customers.catalog,
            enabled: !_saving,
            onAdd: () => setState(() => _customers.add(_CustomerLine())),
            onRemove: (line) => setState(() {
              line.dispose();
              _customers.remove(line);
              if (_customers.isEmpty) _customers.add(_CustomerLine());
            }),
            onChanged: () => setState(() {}),
            total: _customerTotal,
          ),
          const SizedBox(height: 16),
          _SupplierSection(
            lines: _suppliers,
            suppliers: suppliers.catalog,
            enabled: !_saving,
            onAdd: () => setState(() => _suppliers.add(_SupplierLine())),
            onRemove: (line) => setState(() {
              line.dispose();
              _suppliers.remove(line);
              if (_suppliers.isEmpty) _suppliers.add(_SupplierLine());
            }),
            onChanged: () => setState(() {}),
            total: _supplierTotal,
          ),
          const SizedBox(height: 16),
          _InventorySection(
            lines: _inventory,
            enabled: !_saving,
            onAdd: () => setState(() => _inventory.add(_InventoryLine())),
            onRemove: (line) => setState(() {
              line.dispose();
              _inventory.remove(line);
              if (_inventory.isEmpty) _inventory.add(_InventoryLine());
            }),
            onChanged: () => setState(() {}),
            total: _inventoryTotal,
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: s.openingBalanceTotals,
            child: Column(
              children: <Widget>[
                _SummaryRow(label: s.openingCustomers, value: _customerTotal),
                _SummaryRow(label: s.openingInventory, value: _inventoryTotal),
                _SummaryRow(
                  label: s.openingSuppliers,
                  value: -_supplierTotal,
                ),
                const Divider(),
                _SummaryRow(
                  label: s.openingCapital,
                  value: _capital,
                  emphasise: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: s.note,
            child: AppTextField(
              label: s.note,
              controller: _note,
              enabled: !_saving,
              prefixIcon: Icons.notes_outlined,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.how_to_reg_outlined),
            label: Text(s.save),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CustomerSection extends StatelessWidget {
  const _CustomerSection({
    required this.lines,
    required this.customers,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    required this.total,
  });

  final List<_CustomerLine> lines;
  final List<Customer> customers;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<_CustomerLine> onRemove;
  final VoidCallback onChanged;
  final double total;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SectionCard(
      title: s.openingCustomers,
      subtitle: s.openingCustomersHint,
      child: Column(
        children: <Widget>[
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: SearchablePickerField(
                      label: s.customer,
                      value: line.customerId,
                      hint: s.selectCustomer,
                      enabled: enabled,
                      prefixIcon: Icons.person_outline,
                      searchHint: s.searchCustomersHint,
                      options: <PickerOption>[
                        for (final customer in customers)
                          PickerOption(
                            value: customer.id,
                            label: customer.name,
                            subtitle: customer.code,
                            keywords: <String>[
                              if (customer.code != null) customer.code!,
                              if (customer.phone != null) customer.phone!,
                            ],
                          ),
                      ],
                      onChanged: (value) {
                        line.customerId = value;
                        onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: AppNumberField(
                      label: s.expenseAmount,
                      controller: line.amount,
                      enabled: enabled,
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  IconButton(
                    tooltip: s.delete,
                    onPressed: enabled ? () => onRemove(line) : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add),
            label: Text(s.addOpeningLine),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              '${s.total}: ${Formatters.money(total)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierSection extends StatelessWidget {
  const _SupplierSection({
    required this.lines,
    required this.suppliers,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    required this.total,
  });

  final List<_SupplierLine> lines;
  final List<Supplier> suppliers;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<_SupplierLine> onRemove;
  final VoidCallback onChanged;
  final double total;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SectionCard(
      title: s.openingSuppliers,
      subtitle: s.openingSuppliersHint,
      child: Column(
        children: <Widget>[
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: SearchablePickerField(
                      label: s.supplier,
                      value: line.supplierId,
                      hint: s.selectSupplier,
                      enabled: enabled,
                      prefixIcon: Icons.local_shipping_outlined,
                      searchHint: s.searchSuppliersHint,
                      options: <PickerOption>[
                        for (final supplier in suppliers)
                          PickerOption(
                            value: supplier.id,
                            label: supplier.name,
                            subtitle: supplier.code,
                            keywords: <String>[
                              if (supplier.code != null) supplier.code!,
                              if (supplier.phone != null) supplier.phone!,
                            ],
                          ),
                      ],
                      onChanged: (value) {
                        line.supplierId = value;
                        onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: AppNumberField(
                      label: s.expenseAmount,
                      controller: line.amount,
                      enabled: enabled,
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  IconButton(
                    tooltip: s.delete,
                    onPressed: enabled ? () => onRemove(line) : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add),
            label: Text(s.addOpeningLine),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              '${s.total}: ${Formatters.money(total)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _InventorySection extends StatelessWidget {
  const _InventorySection({
    required this.lines,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    required this.total,
  });

  final List<_InventoryLine> lines;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<_InventoryLine> onRemove;
  final VoidCallback onChanged;
  final double total;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SectionCard(
      title: s.openingInventory,
      subtitle: s.openingInventoryHint,
      child: Column(
        children: <Widget>[
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: ProductPickerField(
                              product: line.product,
                              enabled: enabled,
                              onChanged: (value) {
                                line.product = value;
                                if (line.unitCost.text.trim().isEmpty &&
                                    value.costPrice > 0) {
                                  line.unitCost.text =
                                      _formatNumber(value.costPrice);
                                }
                                onChanged();
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: s.delete,
                            onPressed: enabled ? () => onRemove(line) : null,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: AppNumberField(
                              label: s.qty,
                              controller: line.quantity,
                              enabled: enabled,
                              decimal: false,
                              onChanged: (_) => onChanged(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: AppNumberField(
                              label: s.unitCost,
                              controller: line.unitCost,
                              enabled: enabled,
                              onChanged: (_) => onChanged(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add),
            label: Text(s.addOpeningLine),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              '${s.total}: ${Formatters.money(total)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final double value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasise
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(Formatters.money(value), style: style),
        ],
      ),
    );
  }
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toString();
}
