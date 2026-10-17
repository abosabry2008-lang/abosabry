import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../state/settings_controller.dart';

/// Formats a monetary value using [intl].
///
/// The currency is taken from the explicit [currencyCode], then [symbol], then
/// the settings base currency.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.currencyCode,
    this.symbol,
    this.style,
    this.colorNegative = false,
  });

  final num? amount;
  final String? currencyCode;
  final String? symbol;
  final TextStyle? style;
  final bool colorNegative;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController?>();
    final code = currencyCode ?? settings?.baseCurrencyCode;
    final isNegative = (amount ?? 0) < 0;
    final effectiveStyle = colorNegative && isNegative
        ? style?.copyWith(color: Theme.of(context).colorScheme.error) ??
            TextStyle(color: Theme.of(context).colorScheme.error)
        : style;
    return Text(
      Formatters.money(amount, currencyCode: code, symbol: symbol),
      style: effectiveStyle,
    );
  }
}
