import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../core/l10n.dart';

/// A labelled [TextFormField].
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.helperText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.textCapitalization = TextCapitalization.none,
  }) : assert(
          controller == null || initialValue == null,
          'Provide either a controller or an initialValue, not both.',
        );

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final String? helperText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final String? Function(String? value)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffix,
      ),
    );
  }
}

/// A numeric [TextFormField].
class AppNumberField extends StatelessWidget {
  const AppNumberField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.helperText,
    this.prefixIcon,
    this.suffix,
    this.decimal = true,
    this.validator,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
    this.allowNegative = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final String? helperText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool decimal;
  final String? Function(String? value)? validator;
  final ValueChanged<double>? onChanged;
  final bool enabled;
  final bool autofocus;
  final bool allowNegative;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimal,
        signed: allowNegative,
      ),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(
          RegExp(allowNegative
              ? (decimal ? r'[0-9.\-]' : r'[0-9\-]')
              : (decimal ? r'[0-9.]' : r'[0-9]')),
        ),
      ],
      validator: validator,
      onChanged: (value) {
        if (onChanged == null) return;
        onChanged!(double.tryParse(value.trim()) ?? 0);
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffix,
      ),
    );
  }
}

/// One entry of an [AppSelectField].
class SelectOption<T> {
  const SelectOption(this.value, this.label);

  final T value;
  final String label;
}

/// A dropdown backed by [DropdownButtonFormField].
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.validator,
    this.enabled = true,
    this.hint,
    this.prefixIcon,
  });

  final String label;
  final T? value;
  final List<SelectOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String? Function(T? value)? validator;
  final bool enabled;
  final String? hint;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final items = options
        .map(
          (option) => DropdownMenuItem<T>(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList();
    final current = value;
    if (current != null &&
        !options.any((option) => option.value == current)) {
      items.insert(
        0,
        DropdownMenuItem<T>(
          value: current,
          child: const Text('—', overflow: TextOverflow.ellipsis),
        ),
      );
    }
    return DropdownButtonFormField<T>(
      value: current,
      items: items,
      onChanged: enabled ? onChanged : null,
      validator: validator,
      isExpanded: true,
      hint: hint == null ? null : Text(hint!),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      ),
    );
  }
}

/// A read-only date picker field.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
    this.clearable = true,
    this.validator,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;
  final bool clearable;
  final String? Function(DateTime? value)? validator;

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: value,
      validator: validator,
      builder: (state) {
        final selected = value;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled
              ? () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selected ?? now,
                    firstDate: firstDate ?? DateTime(now.year - 5),
                    lastDate: lastDate ?? DateTime(now.year + 5),
                  );
                  if (picked != null) {
                    state.didChange(picked);
                    onChanged(picked);
                  }
                }
              : null,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.event_outlined),
              enabled: enabled,
              errorText: state.errorText,
              suffixIcon: clearable && selected != null
                  ? IconButton(
                      tooltip: context.s.clear,
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: enabled
                          ? () {
                              state.didChange(null);
                              onChanged(null);
                            }
                          : null,
                    )
                  : null,
            ),
            child: Text(
              selected == null ? context.s.selectADate : Formatters.date(selected),
            ),
          ),
        );
      },
    );
  }
}

/// A switch rendered as a list tile.
class AppSwitchField extends StatelessWidget {
  const AppSwitchField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// Debounced search input used at the top of list screens.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.onChanged,
    this.hintText,
    this.initialValue,
    this.debounce = const Duration(milliseconds: 350),
  });

  final ValueChanged<String> onChanged;
  final String? hintText;
  final String? initialValue;
  final Duration debounce;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onChanged(value));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onChanged: _onChanged,
      onSubmitted: (value) {
        _timer?.cancel();
        widget.onChanged(value);
      },
      decoration: InputDecoration(
        hintText: widget.hintText ?? context.s.searchEllipsis,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: context.s.clear,
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  _timer?.cancel();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
    );
  }
}
