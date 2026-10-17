import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../models/product.dart';
import '../../state/categories_controller.dart';
import '../../state/products_controller.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// Create / edit form for a product.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product});

  final Product? product;

  bool get isEditing => product != null;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _sku =
      TextEditingController(text: widget.product?.sku ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.product?.name ?? '');
  late final TextEditingController _barcode =
      TextEditingController(text: widget.product?.barcode ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.product?.description ?? '');
  late final TextEditingController _unit =
      TextEditingController(text: widget.product?.unit ?? 'pc');
  late final TextEditingController _costPrice = TextEditingController(
    text: (widget.product?.costPrice ?? 0).toString(),
  );
  late final TextEditingController _salePrice = TextEditingController(
    text: (widget.product?.salePrice ?? 0).toString(),
  );
  late final TextEditingController _taxRate =
      TextEditingController(text: (widget.product?.taxRate ?? 0).toString());
  late final TextEditingController _reorderLevel = TextEditingController(
    text: (widget.product?.reorderLevel ?? 0).toString(),
  );

  String? _categoryId;
  late bool _trackInventory = widget.product?.trackInventory ?? true;
  late bool _active = widget.product?.active ?? true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.product?.categoryId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CategoriesController>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _barcode.dispose();
    _description.dispose();
    _unit.dispose();
    _costPrice.dispose();
    _salePrice.dispose();
    _taxRate.dispose();
    _reorderLevel.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    setState(() => _saving = true);
    final s = context.s;
    final controller = context.read<ProductsController>();
    final body = <String, dynamic>{
      'sku': _sku.text.trim(),
      'name': _name.text.trim(),
      'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      'categoryId': _categoryId,
      'unit': _unit.text.trim().isEmpty ? 'pc' : _unit.text.trim(),
      'costPrice': double.tryParse(_costPrice.text.trim()) ?? 0,
      'salePrice': double.tryParse(_salePrice.text.trim()) ?? 0,
      'taxRate': double.tryParse(_taxRate.text.trim()) ?? 0,
      'reorderLevel': int.tryParse(_reorderLevel.text.trim()) ?? 0,
      'trackInventory': _trackInventory,
      'active': _active,
    };
    try {
      if (widget.isEditing) {
        await controller.api.patch('/products/${widget.product!.id}', body: body);
      } else {
        await controller.api.post('/products', body: body);
      }
      await controller.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing ? s.productUpdated : s.productCreated,
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final categories = context.watch<CategoriesController>();
    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: s.identification,
              child: Column(
                children: <Widget>[
                  AppTextField(
                    label: s.skuStar,
                    controller: _sku,
                    enabled: !_saving,
                    prefixIcon: Icons.tag,
                    textInputAction: TextInputAction.next,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? s.skuRequired
                        : null,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.nameStar,
                    controller: _name,
                    enabled: !_saving,
                    prefixIcon: Icons.label_outline,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? s.nameRequired
                        : null,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.barcode,
                    controller: _barcode,
                    enabled: !_saving,
                    prefixIcon: Icons.qr_code,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  AppSelectField<String>(
                    label: s.category,
                    value: _categoryId,
                    hint: s.uncategorised,
                    enabled: !_saving,
                    options: <SelectOption<String>>[
                      SelectOption<String>('', s.uncategorised),
                      ...categories.items.map(
                        (category) => SelectOption<String>(
                          category.id,
                          category.name,
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(
                      () => _categoryId =
                          value == null || value.isEmpty ? null : value,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.description,
                    controller: _description,
                    enabled: !_saving,
                    maxLines: 3,
                    prefixIcon: Icons.notes_outlined,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: s.pricingStock,
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AppNumberField(
                          label: s.costPrice,
                          controller: _costPrice,
                          enabled: !_saving,
                          prefixIcon: Icons.attach_money,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppNumberField(
                          label: s.salePrice,
                          controller: _salePrice,
                          enabled: !_saving,
                          prefixIcon: Icons.sell_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AppNumberField(
                          label: s.taxRatePercent,
                          controller: _taxRate,
                          enabled: !_saving,
                          prefixIcon: Icons.percent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppNumberField(
                          label: s.unit,
                          controller: _unit,
                          enabled: !_saving,
                          decimal: false,
                          prefixIcon: Icons.straighten,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AppNumberField(
                    label: s.reorderLevel,
                    controller: _reorderLevel,
                    enabled: !_saving,
                    decimal: false,
                    prefixIcon: Icons.warning_amber_outlined,
                    helperText: s.reorderLevelHelper,
                  ),
                  const SizedBox(height: 8),
                  AppSwitchField(
                    label: s.trackInventory,
                    subtitle: s.trackInventorySubtitle,
                    value: _trackInventory,
                    enabled: !_saving,
                    onChanged: (value) =>
                        setState(() => _trackInventory = value),
                  ),
                  AppSwitchField(
                    label: s.active,
                    subtitle: s.inactiveHiddenSubtitle,
                    value: _active,
                    enabled: !_saving,
                    onChanged: (value) => setState(() => _active = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
