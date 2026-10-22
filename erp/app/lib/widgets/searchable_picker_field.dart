import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/l10n.dart';

/// One selectable row of a [SearchablePickerField].
class PickerOption {
  const PickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.trailing,
    this.keywords = const <String>[],
  });

  final String value;
  final String label;
  final String? subtitle;

  /// Optional right-aligned trailing text (e.g. a balance).
  final String? trailing;

  /// Extra searchable text (code, phone…).
  final List<String> keywords;
}

/// A form field that lets the operator type a name and pick from the matching
/// rows, instead of scrolling a long dropdown of every customer / supplier.
///
/// Tapping the field opens a searchable sheet; the query filters [options] by
/// label, subtitle and keywords as the operator types, and the matching names
/// are listed underneath. Selecting a row closes the sheet and reports the
/// chosen value.
class SearchablePickerField extends StatelessWidget {
  const SearchablePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.hint,
    this.prefixIcon,
    this.searchHint,
    this.clearable = false,
    this.validator,
  });

  final String label;
  final String? value;
  final List<PickerOption> options;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String? hint;
  final IconData? prefixIcon;
  final String? searchHint;

  /// When true a small ✕ clears the current selection.
  final bool clearable;
  final String? Function(String? value)? validator;

  PickerOption? get _selected {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return FormField<String>(
      initialValue: value,
      validator: validator,
      builder: (state) {
        final s = context.s;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled
              ? () async {
                  final picked = await showSearchablePicker(
                    context,
                    title: label,
                    options: options,
                    selected: value,
                    searchHint: searchHint,
                  );
                  if (picked == null) return;
                  onChanged(picked.value == '' ? null : picked.value);
                  state.didChange(picked.value);
                }
              : null,
          child: InputDecorator(
            isEmpty: selected == null,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
              errorText: state.errorText,
              suffixIcon: clearable && selected != null && enabled
                  ? IconButton(
                      tooltip: s.clearField,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        onChanged(null);
                        state.didChange(null);
                      },
                    )
                  : const Icon(Icons.search, size: 18),
            ),
            child: selected == null
                ? null
                : Text(
                    selected.label,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        );
      },
    );
  }
}

/// Opens the searchable selection sheet and resolves with the chosen option
/// (or `null` when dismissed).
Future<PickerOption?> showSearchablePicker(
  BuildContext context, {
  required String title,
  required List<PickerOption> options,
  String? selected,
  String? searchHint,
  bool allowClear = false,
  String? clearLabel,
}) {
  return showModalBottomSheet<PickerOption>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _PickerSheet(
      title: title,
      options: options,
      selected: selected,
      searchHint: searchHint,
      allowClear: allowClear,
      clearLabel: clearLabel,
    ),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchHint,
    required this.allowClear,
    required this.clearLabel,
  });

  final String title;
  final List<PickerOption> options;
  final String? selected;
  final String? searchHint;
  final bool allowClear;
  final String? clearLabel;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<PickerOption> get _filtered {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options.where((option) {
      final haystack = <String>[
        option.label,
        if (option.subtitle != null) option.subtitle!,
        ...option.keywords,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final rows = _filtered;
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.75,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: s.cancel,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.searchHint ?? s.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: s.clearField,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _query.clear();
                            setState(() {});
                          },
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            if (widget.allowClear)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(
                    PickerOption(value: '', label: widget.clearLabel ?? ''),
                  ),
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: Text(widget.clearLabel ?? s.clearField),
                ),
              ),
            const SizedBox(height: 4),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          s.noMatches,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final option = rows[index];
                        final isSelected = option.value == widget.selected;
                        return ListTile(
                          selected: isSelected,
                          leading: isSelected
                              ? Icon(
                                  Icons.check_circle,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          title: Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: option.subtitle == null
                              ? null
                              : Text(
                                  option.subtitle!,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: option.trailing == null
                              ? null
                              : Text(option.trailing!),
                          onTap: () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience for a customer option row.
PickerOption customerPickerOption({
  required String id,
  required String name,
  String? code,
  double? balance,
}) {
  return PickerOption(
    value: id,
    label: name,
    subtitle: code,
    trailing: balance == null ? null : Formatters.money(balance),
    keywords: <String>[],
  );
}
