import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/product.dart';
import '../../models/warehouse.dart';
import '../../widgets/form_fields.dart';
import 'location_picker.dart';
import 'product_picker_field.dart';

/// Opens the "receive stock" dialog. Returns `true` when stock was received.
Future<bool> showReceiveDialog(
  BuildContext context, {
  Product? product,
  Location? location,
  String? warehouseId,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _ReceiveDialog(
      initialProduct: product,
      initialLocation: location,
      initialWarehouseId: warehouseId,
    ),
  );
  return result ?? false;
}

class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog({
    this.initialProduct,
    this.initialLocation,
    this.initialWarehouseId,
  });

  final Product? initialProduct;
  final Location? initialLocation;
  final String? initialWarehouseId;

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late Product? _product = widget.initialProduct;
  late Location? _location = widget.initialLocation;
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _unitCost = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    _unitCost.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final product = _product;
    final location = _location;
    if (product == null || location == null) {
      _snack(context.s.selectProductAndLocation);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<Session>().api.post(
        '/inventory/receive',
        body: <String, dynamic>{
          'productId': product.id,
          'locationId': location.id,
          'quantity': int.tryParse(_quantity.text.trim()) ?? 0,
          'unitCost': double.tryParse(_unitCost.text.trim()) ?? 0,
          'reference':
              _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(context.s.couldNotReceiveStock);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.s.receiveStock),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ProductPickerField(
                product: _product,
                enabled: !_saving,
                onChanged: (value) => setState(() => _product = value),
              ),
              const SizedBox(height: 14),
              LocationPicker(
                value: _location,
                initialWarehouseId: widget.initialWarehouseId,
                onChanged: (value) => setState(() => _location = value),
              ),
              const SizedBox(height: 14),
              AppNumberField(
                label: context.s.quantityStar,
                controller: _quantity,
                enabled: !_saving,
                decimal: false,
                prefixIcon: Icons.numbers,
                validator: (value) {
                  final parsed = int.tryParse((value ?? '').trim());
                  if (parsed == null || parsed <= 0) {
                    return context.s.enterQtyGreaterThanZero;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              AppNumberField(
                label: context.s.unitCost,
                controller: _unitCost,
                enabled: !_saving,
                prefixIcon: Icons.attach_money,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: context.s.reference,
                controller: _reference,
                enabled: !_saving,
                prefixIcon: Icons.receipt_outlined,
                helperText: context.s.supplierInvoiceOrDeliveryNote,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(context.s.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? context.s.posting : context.s.receive),
        ),
      ],
    );
  }
}
