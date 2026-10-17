import 'dart:convert';

import '../core/json_utils.dart';

/// Company-wide settings (`GET/PATCH /settings`).
class AppSettings {
  /// Valid dashboard section keys, in display order.
  static const List<String> dashboardWidgetKeys = <String>[
    'kpis',
    'quickActions',
    'lowStock',
    'recentMovements',
  ];

  /// Parses [dashboardWidgets] (a JSON-encoded array of section keys) into the
  /// set of enabled keys. `null`, an empty/blank string or invalid JSON means
  /// "show everything"; an explicit empty list means "show nothing".
  static Set<String> parseDashboardWidgets(String? raw) {
    final all = dashboardWidgetKeys.toSet();
    if (raw == null || raw.trim().isEmpty) return all;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return all;
      final enabled = decoded
          .whereType<String>()
          .where(dashboardWidgetKeys.contains)
          .toSet();
      // Unrecognised content (non-empty but no known keys) falls back to all.
      if (decoded.isNotEmpty && enabled.isEmpty) return all;
      return enabled;
    } catch (_) {
      return all;
    }
  }

  /// Encodes an enabled-key [Set] into a stable JSON string for persistence.
  static String encodeDashboardWidgets(Set<String> enabled) {
    final ordered = dashboardWidgetKeys.where(enabled.contains).toList();
    return jsonEncode(ordered);
  }

  const AppSettings({
    this.companyName = 'My Company',
    this.companyEmail,
    this.companyPhone,
    this.companyAddress,
    this.baseCurrencyCode = 'USD',
    this.defaultTaxRate = 0,
    this.invoicePrefix = 'INV',
    this.salesOrderPrefix = 'SO',
    this.purchaseOrderPrefix = 'PO',
    this.paymentPrefix = 'PAY',
    this.journalPrefix = 'JE',
    this.lowStockAlerts = true,
    this.taxEnabled = true,
    this.dashboardWidgets,
  });

  final String companyName;
  final String? companyEmail;
  final String? companyPhone;
  final String? companyAddress;
  final String baseCurrencyCode;
  final double defaultTaxRate;
  final String invoicePrefix;
  final String salesOrderPrefix;
  final String purchaseOrderPrefix;
  final String paymentPrefix;
  final String journalPrefix;
  final bool lowStockAlerts;
  final bool taxEnabled;
  final String? dashboardWidgets;

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        companyName: asString(json['companyName'], fallback: 'My Company'),
        companyEmail: asStringOrNull(json['companyEmail']),
        companyPhone: asStringOrNull(json['companyPhone']),
        companyAddress: asStringOrNull(json['companyAddress']),
        baseCurrencyCode:
            asString(json['baseCurrencyCode'], fallback: 'USD'),
        defaultTaxRate: asDouble(json['defaultTaxRate']),
        invoicePrefix: asString(json['invoicePrefix'], fallback: 'INV'),
        salesOrderPrefix: asString(json['salesOrderPrefix'], fallback: 'SO'),
        purchaseOrderPrefix:
            asString(json['purchaseOrderPrefix'], fallback: 'PO'),
        paymentPrefix: asString(json['paymentPrefix'], fallback: 'PAY'),
        journalPrefix: asString(json['journalPrefix'], fallback: 'JE'),
        lowStockAlerts: asBool(json['lowStockAlerts'], fallback: true),
        taxEnabled: asBool(json['taxEnabled'], fallback: true),
        dashboardWidgets: asStringOrNull(json['dashboardWidgets']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'companyName': companyName,
        'companyEmail': companyEmail,
        'companyPhone': companyPhone,
        'companyAddress': companyAddress,
        'baseCurrencyCode': baseCurrencyCode,
        'defaultTaxRate': defaultTaxRate,
        'invoicePrefix': invoicePrefix,
        'salesOrderPrefix': salesOrderPrefix,
        'purchaseOrderPrefix': purchaseOrderPrefix,
        'paymentPrefix': paymentPrefix,
        'journalPrefix': journalPrefix,
        'lowStockAlerts': lowStockAlerts,
        'taxEnabled': taxEnabled,
        'dashboardWidgets': dashboardWidgets,
      };

  AppSettings copyWith({
    String? companyName,
    String? companyEmail,
    String? companyPhone,
    String? companyAddress,
    String? baseCurrencyCode,
    double? defaultTaxRate,
    String? invoicePrefix,
    String? salesOrderPrefix,
    String? purchaseOrderPrefix,
    String? paymentPrefix,
    String? journalPrefix,
    bool? lowStockAlerts,
    bool? taxEnabled,
    String? dashboardWidgets,
  }) =>
      AppSettings(
        companyName: companyName ?? this.companyName,
        companyEmail: companyEmail ?? this.companyEmail,
        companyPhone: companyPhone ?? this.companyPhone,
        companyAddress: companyAddress ?? this.companyAddress,
        baseCurrencyCode: baseCurrencyCode ?? this.baseCurrencyCode,
        defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
        invoicePrefix: invoicePrefix ?? this.invoicePrefix,
        salesOrderPrefix: salesOrderPrefix ?? this.salesOrderPrefix,
        purchaseOrderPrefix: purchaseOrderPrefix ?? this.purchaseOrderPrefix,
        paymentPrefix: paymentPrefix ?? this.paymentPrefix,
        journalPrefix: journalPrefix ?? this.journalPrefix,
        lowStockAlerts: lowStockAlerts ?? this.lowStockAlerts,
        taxEnabled: taxEnabled ?? this.taxEnabled,
        dashboardWidgets: dashboardWidgets ?? this.dashboardWidgets,
      );
}
