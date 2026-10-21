import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// Imports products from a spreadsheet.
///
/// The shop copies four columns straight out of Excel —
/// **name · quantity · cost price · sale price** — and pastes them here. The
/// code column is optional and generated automatically; the sale price is
/// filled as cost + 3% when left empty. An existing code updates that product.
class ProductImportScreen extends StatefulWidget {
  const ProductImportScreen({super.key});

  @override
  State<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends State<ProductImportScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  bool _adjustStock = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Splits one pasted line into cells. Excel copies columns separated by tabs;
  /// commas or semicolons are accepted as a fallback.
  List<String> _splitLine(String line) {
    if (line.contains('\t')) return line.split('\t');
    if (line.contains(';')) return line.split(';');
    return line.split(',');
  }

  bool _looksNumeric(String value) =>
      double.tryParse(value.replaceAll(',', '').trim()) != null;

  /// Parses the pasted text into rows of `{name, quantity, costPrice, salePrice, sku}`.
  /// Column order follows the sheet: الصنف، العدد، سعر التكلفة، سعر البيع [، الكود].
  List<Map<String, dynamic>> _parseRows() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return <Map<String, dynamic>>[];

    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return <Map<String, dynamic>>[];

    var start = 0;
    // Drop a header row such as "الصنف | العدد | سعر التكلفة | سعر البيع".
    final first = _splitLine(lines.first).map((c) => c.trim()).toList();
    if (first.length >= 2 && !_looksNumeric(first[1])) start = 1;

    final rows = <Map<String, dynamic>>[];
    for (var i = start; i < lines.length; i++) {
      final cells = _splitLine(lines[i]).map((c) => c.trim()).toList();
      if (cells.isEmpty) continue;
      final name = cells.isNotEmpty ? cells[0] : '';
      if (name.isEmpty) continue;

      double? toNum(int index) {
        if (cells.length <= index) return null;
        final value = cells[index].replaceAll(',', '').trim();
        if (value.isEmpty) return null;
        return double.tryParse(value);
      }

      // Columns: name (0), quantity (1), costPrice (2), salePrice (3), code (4)
      final quantity = toNum(1);
      final costPrice = toNum(2);
      final salePrice = toNum(3);
      final code = cells.length > 4 ? cells[4].trim() : '';

      rows.add(<String, dynamic>{
        'name': name,
        if (quantity != null) 'quantity': quantity.round(),
        if (costPrice != null) 'costPrice': costPrice,
        if (salePrice != null) 'salePrice': salePrice,
        if (code.isNotEmpty) 'sku': code,
      });
    }
    return rows;
  }

  Future<void> _import() async {
    final s = context.s;
    final rows = _parseRows();
    if (rows.isEmpty) {
      setState(() => _error = s.nothingToImport);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final data = await context.read<Session>().api.postObject(
        '/products/import',
        body: <String, dynamic>{
          'rows': rows,
          'adjustStock': _adjustStock,
        },
      );
      if (!mounted) return;
      setState(() => _result = data);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Import failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final rows = _parseRows();
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: Text(s.importProducts)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: s.importHowTo,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(s.importStep1),
                const SizedBox(height: 6),
                Text(s.importStep2),
                const SizedBox(height: 6),
                Text(s.importStep3),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.importSample,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: s.pasteHere,
            controller: _controller,
            maxLines: 12,
            onChanged: (_) => setState(() {}),
          ),
          if (rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s.rowsDetected(rows.length),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _adjustStock,
            onChanged: (value) => setState(() => _adjustStock = value),
            title: Text(s.adjustStockOnImport),
            subtitle: Text(s.adjustStockOnImportHint),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || rows.isEmpty ? null : _import,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
            label: Text(s.importNow),
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: 16),
            _ImportSummary(result: result),
          ],
        ],
      ),
    );
  }
}

class _ImportSummary extends StatelessWidget {
  const _ImportSummary({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final created = result['created'] ?? 0;
    final updated = result['updated'] ?? 0;
    final skipped = result['skipped'] ?? 0;
    final rows = (result['rows'] is List)
        ? (result['rows'] as List).whereType<Map>().toList()
        : const <Map>[];

    return SectionCard(
      title: s.importResult,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${s.importCreated}: $created · ${s.importUpdated}: $updated · '
            '${s.importSkipped}: $skipped',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final row in rows.where((r) => r['action'] == 'created'))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• ${row['name']} — ${row['sku']}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          for (final row in rows.where((r) => r['action'] == 'skipped'))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• ${row['name']} — ${row['reason']}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
