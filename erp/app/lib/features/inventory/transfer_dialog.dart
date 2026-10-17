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

/// Opens the stock transfer dialog. Returns `true` when a transfer was posted.
Future<bool> showTransferDialog(
  BuildContext context, {
  Product? product,
  Location? fromLocation,
  String? warehouseId,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _TransferDialog(
      initialProduct: product,
      initialFromLocation: fromLocation,
      initialWarehouseId: warehouseId,
    ),
  );
  return result ?? false;
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({
    this.initialProduct,
    this.initialFromLocation,
    this.initialWarehouseId,
  });

  final Product? initialProduct;
  final Location? initialFromLocation;
  final String? initialWarehouseId;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late Product? _product = widget.initialProduct;
  late Location? _from = widget.initialFromLocation;
  Location? _to;
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final product = _product;
    final from = _from;
    final to = _to;
    if (product == null || from == null || to == null) {
      _snack(context.s.selectProductSourceDestination);
      return;
    }
    if (from.id == to.id) {
      _snack(context.s.sourceDestinationDiffer);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<Session>().api.post(
        '/inventory/transfer',
        body: <String, dynamic>{
          'productId': product.id,
          'fromLocationId': from.id,
          'toLocationId': to.id,
          'quantity': int.tryParse(_quantity.text.trim()) ?? 0,
          'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
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
      _snack(context.s.couldNotPostTransfer);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.s.transferStock),
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
              Text(
                context.s.from,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              LocationPicker(
                value: _from,
                initialWarehouseId: widget.initialWarehouseId,
                onChanged: (value) => setState(() => _from = value),
              ),
              const SizedBox(height: 14),
              Text(
                context.s.to,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              LocationPicker(
                value: _to,
                onChanged: (value) => setState(() => _to = value),
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
              AppTextField(
                label: context.s.note,
                controller: _note,
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
          child: Text(_saving ? context.s.posting : context.s.transfer),
        ),
      ],
    );
  }
}
