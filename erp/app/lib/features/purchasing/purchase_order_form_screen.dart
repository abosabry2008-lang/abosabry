import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/warehouse.dart';
import '../../state/purchase_orders_controller.dart';
import '../../state/suppliers_controller.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/order_lines_editor.dart';
import '../../widgets/section_card.dart';

/// Create form for a purchase order.
class PurchaseOrderFormScreen extends StatefulWidget {
  const PurchaseOrderFormScreen({super.key});

  @override
  State<PurchaseOrderFormScreen> createState() =>
      _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState extends State<PurchaseOrderFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final List<OrderLineDraft> _lines = <OrderLineDraft>[OrderLineDraft()];

  List<Warehouse> _warehouses = <Warehouse>[];
  String? _supplierId;
  String? _warehouseId;
  DateTime? _expectedDate;
  final TextEditingController _notes = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SuppliersController>().ensureLoaded();
      _loadWarehouses();
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
      });
    } catch (_) {
      // Leave the dropdown empty; validation will block submission.
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_supplierId == null || _warehouseId == null) {
      _snack(context.s.selectSupplierAndWarehouse);
      return;
    }
    final validLines = _lines.where((line) => line.isValid).toList();
    if (validLines.isEmpty) {
      _snack(context.s.addAtLeastOneCompleteLine);
      return;
    }
    setState(() => _saving = true);
    final controller = context.read<PurchaseOrdersController>();
    try {
      await controller.api.post(
        '/purchase-orders',
        body: <String, dynamic>{
          'supplierId': _supplierId,
          'warehouseId': _warehouseId,
          'expectedDate': _expectedDate?.toIso8601String(),
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          'lines': validLines
              .map(
                (line) => <String, dynamic>{
                  'productId': line.product!.id,
                  'quantity': line.quantity,
                  'unitCost': line.price,
                  'taxRate': line.taxRate,
                },
              )
              .toList(),
        },
      );
      await controller.refresh();
      if (!mounted) return;
      _snack(context.s.purchaseOrderCreated);
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      _snack(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final suppliers = context.watch<SuppliersController>();

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
                  AppSelectField<String>(
                    label: s.supplierStar,
                    value: _supplierId,
                    enabled: !_saving,
                    prefixIcon: Icons.local_shipping_outlined,
                    options: suppliers.items
                        .map(
                          (supplier) => SelectOption<String>(
                            supplier.id,
                            supplier.name,
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _supplierId = value),
                    validator: (value) =>
                        value == null ? s.supplierRequired : null,
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
                  AppDateField(
                    label: s.expectedDate,
                    value: _expectedDate,
                    enabled: !_saving,
                    onChanged: (value) => setState(() => _expectedDate = value),
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
              subtitle: s.productsToOrder,
              child: OrderLinesEditor(
                lines: _lines,
                enabled: !_saving,
                priceLabel: s.unitCost,
                onChanged: () => setState(() {}),
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
                    label: Text(_saving ? s.saving : s.createOrder),
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
