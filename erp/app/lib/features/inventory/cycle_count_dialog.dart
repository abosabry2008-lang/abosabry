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

/// Opens the cycle-count dialog. Returns `true` when a count was submitted.
Future<bool> showCycleCountDialog(
  BuildContext context, {
  Location? location,
  String? warehouseId,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _CycleCountDialog(
      initialLocation: location,
      initialWarehouseId: warehouseId,
    ),
  );
  return result ?? false;
}

class _CountLine {
  _CountLine(this.product) : controller = TextEditingController();

  Product product;
  final TextEditingController controller;

  void dispose() => controller.dispose();
}

class _CycleCountDialog extends StatefulWidget {
  const _CycleCountDialog({this.initialLocation, this.initialWarehouseId});

  final Location? initialLocation;
  final String? initialWarehouseId;

  @override
  State<_CycleCountDialog> createState() => _CycleCountDialogState();
}

class _CycleCountDialogState extends State<_CycleCountDialog> {
  late Location? _location = widget.initialLocation;
  final List<_CountLine> _lines = <_CountLine>[];
  bool _saving = false;

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    setState(() => _lines.add(_CountLine(Product(
          id: '',
          sku: '',
          name: '',
        ))));
  }

  Future<void> _submit() async {
    final location = _location;
    final s = context.s;
    if (location == null) {
      _snack(s.selectLocationToCount);
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (final line in _lines) {
      if (line.product.id.isEmpty) {
        _snack(s.selectProductEveryLine);
        return;
      }
      final counted = int.tryParse(line.controller.text.trim());
      if (counted == null) {
        _snack(s.enterCountedEveryLine);
        return;
      }
      items.add(<String, dynamic>{
        'productId': line.product.id,
        'countedQty': counted,
      });
    }
    if (items.isEmpty) {
      _snack(s.addAtLeastOneProduct);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<Session>().api.post(
        '/inventory/cycle-count',
        body: <String, dynamic>{
          'locationId': location.id,
          'items': items,
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
      _snack(context.s.couldNotSubmitCycleCount);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AlertDialog(
      title: Text(s.cycleCount),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LocationPicker(
                value: _location,
                initialWarehouseId: widget.initialWarehouseId,
                onChanged: (value) => setState(() => _location = value),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      s.countedItems,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saving ? null : _addLine,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.add),
                  ),
                ],
              ),
              if (_lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    s.noItemsYet,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              for (var index = 0; index < _lines.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: ProductPickerField(
                          label: _lines[index].product.id.isEmpty
                              ? s.product
                              : _lines[index].product.name,
                          product: _lines[index].product.id.isEmpty
                              ? null
                              : _lines[index].product,
                          enabled: !_saving,
                          onChanged: (value) {
                            setState(() => _lines[index].product = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: AppNumberField(
                          label: s.counted,
                          controller: _lines[index].controller,
                          enabled: !_saving,
                          decimal: false,
                        ),
                      ),
                      IconButton(
                        tooltip: s.removeLine,
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                  _lines.removeAt(index).dispose();
                                }),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? s.submitting : s.submitCount),
        ),
      ],
    );
  }
}
