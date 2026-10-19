import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../models/purchase_order.dart';
import '../../state/purchase_orders_controller.dart';
import '../../state/product_catalog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/order_lines_editor.dart';
import '../../widgets/section_card.dart';

/// Edits a purchase order (drafts for everyone; admins may also edit
/// not-yet-received approved orders).
class PurchaseOrderEditScreen extends StatefulWidget {
  const PurchaseOrderEditScreen({super.key, required this.order});

  final PurchaseOrder order;

  @override
  State<PurchaseOrderEditScreen> createState() =>
      _PurchaseOrderEditScreenState();
}

class _PurchaseOrderEditScreenState extends State<PurchaseOrderEditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final List<OrderLineDraft> _lines = widget.order.lines
      .map(
        (line) => OrderLineDraft(
          quantity: line.quantity.toDouble(),
          price: line.unitCost,
          taxRate: line.taxRate,
        ),
      )
      .toList();

  late DateTime? _expectedDate = widget.order.expectedDate;
  late final TextEditingController _notes =
      TextEditingController(text: widget.order.notes ?? '');
  bool _linesDirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_lines.isEmpty) _lines.add(OrderLineDraft());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final catalog = context.read<ProductCatalog>();
      await catalog.ensureLoaded();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _lines.length && i < widget.order.lines.length; i++) {
          _lines[i].product ??= catalog.byId(widget.order.lines[i].productId);
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

  void _linesChanged() {
    _linesDirty = true;
    setState(() {});
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final s = context.s;
    if (_linesDirty &&
        (_lines.isEmpty || _lines.any((line) => !line.isValid))) {
      _snack(s.eachLineNeedsProduct);
      return;
    }
    setState(() => _saving = true);
    final controller = context.read<PurchaseOrdersController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await controller.api.patch(
        '/purchase-orders/${widget.order.id}',
        body: <String, dynamic>{
          'expectedDate': _expectedDate?.toIso8601String(),
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          if (_linesDirty)
            'lines': _lines
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
      messenger.showSnackBar(SnackBar(content: Text(s.purchaseOrderUpdated)));
      navigator.pop(true);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
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
    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: s.editOrder,
              subtitle: widget.order.number,
              child: Column(
                children: <Widget>[
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
                onChanged: _linesChanged,
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
                    label: Text(_saving ? s.saving : s.save),
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
