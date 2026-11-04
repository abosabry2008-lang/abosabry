import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/product.dart';
import '../../models/warehouse.dart';
import '../../state/warehouses_controller.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import 'product_picker_field.dart';

/// A multi-line stock transfer voucher between two warehouses.
///
/// The form works like the sales-invoice entry: one header (source and
/// destination warehouse plus a note) and as many product lines as needed. All
/// lines are posted in one transaction under a single `TRF-…` voucher number.
class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({
    super.key,
    this.initialProduct,
    this.initialFromLocation,
    this.initialWarehouseId,
  });

  final Product? initialProduct;
  final Location? initialFromLocation;
  final String? initialWarehouseId;

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _TransferLine {
  _TransferLine({this.product, String? sellUnit})
      : sellUnit = sellUnit ?? _defaultUnit(product);

  Product? product;
  String sellUnit;
  final TextEditingController quantity = TextEditingController();

  int get quantityValue => int.tryParse(quantity.text.trim()) ?? 0;

  int get boxes {
    final bpc = product?.boxesPerCarton ?? 0;
    return sellUnit == 'carton' && bpc > 0
        ? quantityValue * bpc
        : quantityValue;
  }

  static String _defaultUnit(Product? product) =>
      (product?.boxesPerCarton ?? 0) > 0 ? 'carton' : 'unit';

  void dispose() => quantity.dispose();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  final TextEditingController _note = TextEditingController();
  final List<_TransferLine> _lines = <_TransferLine>[];
  List<Warehouse> _warehouses = <Warehouse>[];
  Map<String, int> _availability = <String, int>{};
  String? _fromWarehouseId;
  String? _toWarehouseId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lines.add(_TransferLine(product: widget.initialProduct));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWarehouses());
  }

  @override
  void dispose() {
    _note.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadWarehouses() async {
    try {
      final controller = context.read<WarehousesController>();
      await controller.ensureLoaded();
      if (!mounted) return;
      final warehouses = controller.items;
      var fromId = widget.initialFromLocation?.warehouseId ??
          widget.initialWarehouseId;
      if (fromId == null || !warehouses.any((row) => row.id == fromId)) {
        fromId = warehouses.isNotEmpty ? warehouses.first.id : null;
      }
      var toId = _otherWarehouse(warehouses, fromId);
      setState(() {
        _warehouses = warehouses;
        _fromWarehouseId = fromId;
        _toWarehouseId = toId;
        _loading = false;
      });
      await _loadAvailability();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.s.couldNotLoadReport;
      });
    }
  }

  Future<void> _loadAvailability() async {
    final warehouseId = _fromWarehouseId;
    if (warehouseId == null) {
      if (mounted) setState(() => _availability = <String, int>{});
      return;
    }
    try {
      final rows = await context.read<Session>().api.getList(
            '/inventory/availability',
            query: <String, dynamic>{'warehouseId': warehouseId},
          );
      if (!mounted) return;
      final next = <String, int>{};
      for (final row in rows) {
        final productId = asString(row['productId']);
        if (productId.isNotEmpty) next[productId] = asInt(row['quantity']);
      }
      setState(() => _availability = next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _availability = <String, int>{});
    }
  }

  String? _otherWarehouse(List<Warehouse> warehouses, String? fromId) {
    for (final warehouse in warehouses) {
      if (warehouse.id != fromId) return warehouse.id;
    }
    return null;
  }

  void _addLine() {
    setState(() => _lines.add(_TransferLine()));
  }

  void _removeLine(int index) {
    if (_lines.length == 1) {
      setState(() {
        _lines.first.dispose();
        _lines[0] = _TransferLine();
      });
      return;
    }
    setState(() {
      _lines.removeAt(index).dispose();
    });
  }

  int get _totalBoxes =>
      _lines.fold<int>(0, (sum, line) => sum + (line.product == null ? 0 : line.boxes));

  bool get _hasAnyProduct =>
      _lines.any((line) => line.product != null && line.quantityValue > 0);

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final s = context.s;
    final fromId = _fromWarehouseId;
    final toId = _toWarehouseId;
    if (fromId == null || toId == null) {
      _snack(s.selectWarehouse);
      return;
    }
    if (fromId == toId) {
      _snack(s.transferWarehousesDiffer);
      return;
    }
    if (!_hasAnyProduct) {
      _snack(s.transferNoItems);
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final product = line.product;
      if (product == null || line.quantityValue <= 0) continue;
      final available = _availability[product.id] ?? 0;
      if (line.boxes > available) {
        _snack(
          '${product.name}: ${s.available} ${_packLabel(available, product.boxesPerCarton)}',
        );
        return;
      }
      items.add(<String, dynamic>{
        'productId': product.id,
        'quantity': line.quantityValue,
        'sellUnit': line.sellUnit,
      });
    }
    if (items.isEmpty) {
      _snack(s.transferNoItems);
      return;
    }

    setState(() => _saving = true);
    try {
      await context.read<Session>().api.post(
        '/inventory/transfers',
        body: <String, dynamic>{
          'fromWarehouseId': fromId,
          'toWarehouseId': toId,
          'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
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
      _snack(context.s.couldNotPostTransfer);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_warehouses.isEmpty) {
      return Center(child: Text(s.selectWarehouse));
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: <Widget>[
              SectionCard(
                title: s.transferVoucher,
                subtitle: s.transferVoucherHint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppSelectField<String>(
                            label: s.from,
                            value: _fromWarehouseId,
                            prefixIcon: Icons.warehouse_outlined,
                            options: <SelectOption<String>>[
                              for (final warehouse in _warehouses)
                                SelectOption<String>(
                                  warehouse.id,
                                  '${warehouse.name} (${warehouse.code})',
                                ),
                            ],
                            onChanged: _saving
                                ? (_) {}
                                : (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _fromWarehouseId = value;
                                      if (_toWarehouseId == value) {
                                        _toWarehouseId = _otherWarehouse(
                                          _warehouses,
                                          value,
                                        );
                                      }
                                    });
                                    _loadAvailability();
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppSelectField<String>(
                            label: s.to,
                            value: _toWarehouseId,
                            prefixIcon: Icons.warehouse_outlined,
                            options: <SelectOption<String>>[
                              for (final warehouse in _warehouses)
                                if (warehouse.id != _fromWarehouseId)
                                  SelectOption<String>(
                                    warehouse.id,
                                    '${warehouse.name} (${warehouse.code})',
                                  ),
                            ],
                            onChanged: _saving
                                ? (_) {}
                                : (value) =>
                                    setState(() => _toWarehouseId = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: s.note,
                      controller: _note,
                      enabled: !_saving,
                      prefixIcon: Icons.notes_outlined,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: s.lines,
                subtitle: s.transferVoucherHint,
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                child: Column(
                  children: <Widget>[
                    for (var index = 0; index < _lines.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == _lines.length - 1 ? 0 : 8,
                        ),
                        child: _buildLine(context, index),
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _addLine,
                        icon: const Icon(Icons.add),
                        label: Text(s.addLine),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildFooter(context),
      ],
    );
  }

  Widget _buildLine(BuildContext context, int index) {
    final s = context.s;
    final line = _lines[index];
    final product = line.product;
    final bpc = product?.boxesPerCarton ?? 0;
    final available = product == null ? null : (_availability[product.id] ?? 0);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ProductPickerField(
                  product: line.product,
                  label: s.product,
                  enabled: !_saving,
                  onChanged: (value) {
                    setState(() {
                      line.product = value;
                      line.sellUnit = _TransferLine._defaultUnit(value);
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: s.removeLine,
                onPressed: _saving ? null : () => _removeLine(index),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: AppNumberField(
                  label: s.quantity,
                  controller: line.quantity,
                  enabled: !_saving,
                  decimal: false,
                  dense: true,
                  prefixIcon: Icons.numbers,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 150,
                child: AppSelectField<String>(
                  label: s.unit,
                  value: line.sellUnit,
                  enabled: !_saving,
                  options: _unitOptions(context, bpc),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => line.sellUnit = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  available == null
                      ? s.available
                      : '${s.available}: ${_packLabel(available, bpc)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (product != null && line.quantityValue > 0)
                Text(
                  '= ${line.boxes} ${s.box}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final lineCount = _lines.where((line) => line.product != null).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Wrap(
              spacing: 20,
              runSpacing: 6,
              children: <Widget>[
                _FooterStat(label: s.lineCountLabel, value: '$lineCount'),
                _FooterStat(label: s.totalInBoxes, value: '$_totalBoxes'),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz),
            label: Text(_saving ? s.posting : s.transfer),
          ),
        ],
      ),
    );
  }

  List<SelectOption<String>> _unitOptions(BuildContext context, int bpc) {
    final s = context.s;
    if (bpc <= 0) {
      return <SelectOption<String>>[
        SelectOption<String>('unit', s.box),
      ];
    }
    return <SelectOption<String>>[
      SelectOption<String>('carton', s.carton),
      SelectOption<String>('box', s.box),
    ];
  }

  String _packLabel(int quantity, int boxesPerCarton) {
    if (boxesPerCarton <= 0) return '$quantity ${context.s.box}';
    return context.s.packStock(
      quantity ~/ boxesPerCarton,
      quantity % boxesPerCarton,
    );
  }
}

class _FooterStat extends StatelessWidget {
  const _FooterStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
