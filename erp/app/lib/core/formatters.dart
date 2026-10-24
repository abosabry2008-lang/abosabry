import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formatting helpers for money, numbers, dates and status labels.
class Formatters {
  Formatters._();

  static const Map<String, String> _symbols = <String, String>{
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'NGN': '₦',
    'KES': 'KSh ',
    'GHS': 'GH₵',
    'ZAR': 'R',
    'EGP': 'E£',
    'INR': '₹',
    'JPY': '¥',
    'CNY': '¥',
    'AED': 'AED ',
    'SAR': 'SAR ',
    'CAD': r'C$',
    'AUD': r'A$',
    'CHF': 'CHF ',
  };

  static final NumberFormat _money = NumberFormat('#,##0.00');

  /// Symbol for a currency code, falling back to `CODE `.
  static String symbolFor(String? currencyCode) {
    final code = (currencyCode ?? 'USD').toUpperCase();
    final symbol = _symbols[code];
    if (symbol != null) return symbol;
    return code.isEmpty ? r'$' : '$code ';
  }

  /// Formats an amount using [intl], respecting an optional [symbol] or
  /// [currencyCode].
  static String money(
    num? amount, {
    String? currencyCode,
    String? symbol,
  }) {
    final prefix = symbol ?? symbolFor(currencyCode);
    final value = amount ?? 0;
    final negative = value < 0;
    final formatted = _money.format(value.abs());
    return negative ? '-$prefix$formatted' : '$prefix$formatted';
  }

  /// Formats a plain number with a fixed number of decimals.
  static String number(num? value, {int decimals = 2}) =>
      NumberFormat.decimalPatternDigits(locale: 'en', decimalDigits: decimals)
          .format(value ?? 0);

  /// Formats an integer with thousands separators.
  static String integer(num? value) =>
      NumberFormat.decimalPattern('en').format(value ?? 0);

  /// Formats a percentage value (already expressed as 0-100).
  static String percent(num? value, {int decimals = 2}) =>
      '${(value ?? 0).toStringAsFixed(decimals)}%';

  /// Short date, e.g. `Oct 16, 2026`.
  static String date(DateTime? value) =>
      value == null ? '-' : DateFormat.yMMMd().format(value.toLocal());

  /// Date and time, e.g. `Oct 16, 2026 14:05`.
  static String dateTime(DateTime? value) =>
      value == null ? '-' : DateFormat.yMMMd().add_Hm().format(value.toLocal());

  /// ISO date used by API query parameters.
  static String isoDate(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(value);

  /// ISO instant for the end of the given local calendar day, in UTC.
  ///
  /// Date pickers return midnight, so a range ending on that raw value would
  /// drop everything that happened during the selected day.
  static String isoRangeEnd(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999)
          .toUtc()
          .toIso8601String();

  /// Converts `PARTIALLY_RECEIVED` into `Partially received`.
  static String label(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    return raw
        .split(RegExp('[_\\s]+'))
        .where((word) => word.isNotEmpty)
        .map((word) =>
            word.length == 1 ? word.toUpperCase() : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  /// Colour associated with a business status value.
  static Color statusColor(BuildContext context, String? status) {
    final scheme = Theme.of(context).colorScheme;
    switch ((status ?? '').toUpperCase()) {
      case 'DRAFT':
        return scheme.outline;
      case 'PENDING':
      case 'PARTIALLY_RECEIVED':
      case 'PARTIALLY_FULFILLED':
      case 'PARTIALLY_PAID':
        return const Color(0xFFB26A00);
      case 'APPROVED':
      case 'CONFIRMED':
        return const Color(0xFF1565C0);
      case 'RECEIVED':
      case 'FULFILLED':
      case 'PAID':
      case 'ACTIVE':
      case 'ISSUED':
        return const Color(0xFF2E7D32);
      case 'CANCELLED':
      case 'VOID':
      case 'INACTIVE':
      case 'OVERDUE':
        return scheme.error;
      default:
        return scheme.primary;
    }
  }

  /// Icon associated with a business status value.
  static IconData statusIcon(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'DRAFT':
        return Icons.edit_note;
      case 'PENDING':
        return Icons.hourglass_empty;
      case 'APPROVED':
      case 'CONFIRMED':
      case 'ISSUED':
        return Icons.verified_outlined;
      case 'PARTIALLY_RECEIVED':
      case 'PARTIALLY_FULFILLED':
      case 'PARTIALLY_PAID':
        return Icons.timelapse;
      case 'RECEIVED':
      case 'FULFILLED':
      case 'PAID':
        return Icons.check_circle_outline;
      case 'CANCELLED':
      case 'VOID':
        return Icons.cancel_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}
