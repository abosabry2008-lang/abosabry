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

/// Opens the stock adjustment dialog. Returns `true` when an adjustment was
/// posted.
Future<bool> showAdjustDialog(
  BuildContext context, {
  Product? product,
  Location? location,
  String? warehouseId,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _AdjustDialog(
      initialProduct: product,
      initialLocation: location,
      initialWarehouseId: warehouseId,
    ),
  );
  return result ?? false;
}

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({
    this.initialProduct,
    this.initialLocation,
    this.initialWarehouseId,
  });

  final Product? initialProduct;
  final Location? initialLocation;
  final String? initialWarehouseId;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late Product? _product = widget.initialProduct;
  late Location? _location = widget.initialLocation;
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final product = _product;
    final location = _location;
    if (product == null) {
      _snack(context.s.selectAProduct);
      return;
    }
    if (location == null) {
      _snack(context.s.selectALocation);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<Session>().api.post(
        '/inventory/adjust',
        body: <String, dynamic>{
          'productId': product.id,
          'locationId': location.id,
          'quantity': int.tryParse(_quantity.text.trim()) ?? 0,
          'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
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
      _snack(context.s.couldNotPostAdjustment);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.s.adjustStock),
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
                onChanged: (value) {
                  setState(() => _product = value);
                },
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
                allowNegative: true,
                prefixIcon: Icons.exposure,
                helperText: context.s.positiveAddsStock,
                validator: (value) {
                  final parsed = int.tryParse((value ?? '').trim());
                  if (parsed == null) return context.s.enterWholeNumber;
                  if (parsed == 0) return context.s.enterNonZeroQuantity;
                  return null;
                },
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: context.s.reason,
                controller: _reason,
                enabled: !_saving,
                prefixIcon: Icons.notes_outlined,
                textCapitalization: TextCapitalization.sentences,
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
          child: Text(_saving ? context.s.posting : context.s.postAdjustment),
        ),
      ],
    );
  }
}
