import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/warehouse.dart';
import '../../widgets/form_fields.dart';

/// Warehouse + location selector used by the inventory dialogs.
class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    required this.onChanged,
    this.value,
    this.initialWarehouseId,
  });

  /// Currently selected location.
  final Location? value;

  /// Called whenever the selection changes.
  final ValueChanged<Location?> onChanged;

  /// Pre-selects a warehouse (used when adjusting a known stock row).
  final String? initialWarehouseId;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  List<Warehouse> _warehouses = <Warehouse>[];
  List<Location> _locations = <Location>[];
  String? _warehouseId;
  bool _loadingWarehouses = false;
  bool _loadingLocations = false;
  String? _error;

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _warehouseId = widget.initialWarehouseId ?? widget.value?.warehouseId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    await _loadWarehouses();
    if (_warehouseId != null) {
      await _loadLocations(_warehouseId!);
    }
  }

  Future<void> _loadWarehouses() async {
    setState(() {
      _loadingWarehouses = true;
      _error = null;
    });
    try {
      final page = await _api.getPage<Warehouse>(
        '/warehouses',
        query: <String, dynamic>{'page': 1, 'pageSize': 100},
        parse: Warehouse.fromJson,
      );
      setState(() => _warehouses = page.items);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      setState(() => _loadingWarehouses = false);
    }
  }

  Future<void> _loadLocations(String warehouseId) async {
    setState(() {
      _loadingLocations = true;
      _error = null;
    });
    try {
      final json = await _api.get('/warehouses/$warehouseId/locations');
      final data = asMap(json)['data'];
      final rows = data is List
          ? asMapList(data)
          : asMapList(asMap(data)['items']);
      setState(() => _locations = rows.map(Location.fromJson).toList());
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      setState(() => _loadingLocations = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSelectField<String>(
          label: s.warehouse,
          value: _warehouseId,
          hint: s.selectAWarehouse,
          prefixIcon: Icons.warehouse_outlined,
          enabled: !_loadingWarehouses,
          options: _warehouses
              .map(
                (warehouse) => SelectOption<String>(
                  warehouse.id,
                  '${warehouse.code} — ${warehouse.name}',
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _warehouseId = value;
              _locations = <Location>[];
            });
            widget.onChanged(null);
            if (value != null) _loadLocations(value);
          },
        ),
        const SizedBox(height: 14),
        if (_loadingLocations)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          AppSelectField<String>(
            label: s.location,
            value: widget.value?.id,
            hint: _warehouseId == null
                ? s.chooseWarehouseFirst
                : s.selectALocation,
            prefixIcon: Icons.place_outlined,
            enabled: _warehouseId != null,
            options: _locations
                .map(
                  (location) => SelectOption<String>(location.id, location.label),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                widget.onChanged(null);
                return;
              }
              for (final location in _locations) {
                if (location.id == value) {
                  widget.onChanged(location);
                  return;
                }
              }
            },
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
