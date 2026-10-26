import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/json_utils.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../models/category.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'report_widgets.dart';

/// Sale price list: all products or only those with stock on hand.
class PriceListScreen extends StatefulWidget {
  const PriceListScreen({super.key});

  @override
  State<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends State<PriceListScreen> {
  bool _availableOnly = false;
  String? _categoryId;
  List<Category> _categories = <Category>[];
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
      _load();
    });
  }

  Future<void> _loadCategories() async {
    try {
      final rows =
          await context.read<Session>().api.getList('/categories');
      if (!mounted) return;
      setState(() => _categories = rows.map(Category.fromJson).toList());
    } on ApiException {
      // The category filter is optional.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<Session>().api.getObject(
            '/reports/price-list',
            query: <String, dynamic>{
              'availableOnly': _availableOnly ? 'true' : 'false',
              if (_categoryId != null && _categoryId!.isNotEmpty)
                'categoryId': _categoryId,
            },
          );
      if (!mounted) return;
      setState(() => _rows = asMapList(data['rows']));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return ReportAsyncSection(
      loading: _loading,
      error: _error,
      isEmpty: _rows.isEmpty,
      emptyTitle: s.noDataForFilters,
      onRetry: _load,
      header: ReportHeader(
        onPrint: () => PrintService.printPriceList(
          context,
          availableOnly: _availableOnly,
          categoryId: _categoryId,
        ),
        filters: <Widget>[
          SegmentedButton<bool>(
            segments: <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: false, label: Text(s.allProducts)),
              ButtonSegment<bool>(
                value: true,
                label: Text(s.availableOnly),
              ),
            ],
            selected: <bool>{_availableOnly},
            onSelectionChanged: (values) {
              setState(() => _availableOnly = values.first);
              _load();
            },
          ),
          AppSelectField<String>(
            label: s.category,
            value: _categoryId ?? '',
            hint: s.allCategories,
            prefixIcon: Icons.category_outlined,
            options: <SelectOption<String>>[
              SelectOption<String>('', s.allCategories),
              for (final category in _categories)
                SelectOption<String>(category.id, category.name),
            ],
            onChanged: (value) {
              setState(() =>
                  _categoryId = (value == null || value.isEmpty) ? null : value);
              _load();
            },
          ),
        ],
      ),
      children: <Widget>[
        SectionCard(
          title: s.priceList,
          subtitle: s.productCountLabel('${_rows.length}'),
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 20,
              columns: <DataColumn>[
                DataColumn(label: Text(s.product)),
                DataColumn(label: Text(s.code)),
                DataColumn(label: Text(s.category)),
                DataColumn(label: Text(s.available), numeric: true),
                DataColumn(label: Text(s.unit)),
                DataColumn(label: Text(s.salePrice), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in _rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 280,
                          child: Text(
                            asString(row['name']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(asString(row['sku']))),
                      DataCell(
                        Text(
                          asStringOrNull(row['category']) ?? '—',
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.integer(asDouble(row['quantity'])),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      DataCell(Text(asString(row['unit']))),
                      DataCell(MoneyText(asDouble(row['salePrice']))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
