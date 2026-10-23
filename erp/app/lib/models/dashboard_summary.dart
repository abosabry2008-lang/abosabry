import '../core/json_utils.dart';
import 'sales_point.dart';

/// Aggregated KPIs returned by `GET /reports/dashboard`.
///
/// The backend shape may vary, so every value is parsed defensively from a
/// handful of plausible keys and the original payload is kept in [raw].
class DashboardSummary {
  const DashboardSummary({
    this.salesToday = 0,
    this.salesThisMonth = 0,
    this.receivables = 0,
    this.inventoryValue = 0,
    this.lowStockCount = 0,
    this.productCount = 0,
    this.customerCount = 0,
    this.supplierCount = 0,
    this.salesOrderCount = 0,
    this.purchaseOrderCount = 0,
    this.invoiceCount = 0,
    this.currencyCode,
    this.topProducts = const <SalesPoint>[],
    this.salesTrend = const <SalesPoint>[],
    this.movements = const <Map<String, dynamic>>[],
  });

  final double salesToday;
  final double salesThisMonth;
  final double receivables;
  final double inventoryValue;
  final int lowStockCount;
  final int productCount;
  final int customerCount;
  final int supplierCount;
  final int salesOrderCount;
  final int purchaseOrderCount;
  final int invoiceCount;
  final String? currencyCode;
  final List<SalesPoint> topProducts;
  final List<SalesPoint> salesTrend;
  final List<Map<String, dynamic>> movements;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final sales = asMap(json['sales']);
    final inventory = asMap(json['inventory']);
    final counts = asMap(json['counts']);
    final settings = asMap(json['settings']);

    double pick(List<dynamic> values) {
      for (final value in values) {
        if (value != null) return asDouble(value);
      }
      return 0;
    }

    int pickInt(List<dynamic> values) {
      for (final value in values) {
        if (value != null) return asInt(value);
      }
      return 0;
    }

    return DashboardSummary(
      salesToday: pick(<dynamic>[json['salesToday'], sales['today']]),
      salesThisMonth: pick(<dynamic>[
        json['salesThisMonth'],
        sales['thisMonth'],
        sales['month'],
        sales['total'],
      ]),
      receivables: pick(<dynamic>[
        json['receivables'],
        json['outstandingReceivables'],
        sales['receivables'],
        sales['outstanding'],
      ]),
      inventoryValue: pick(<dynamic>[
        json['inventoryValue'],
        inventory['value'],
        inventory['totalValue'],
        // The dashboard report returns `inventory.costValue` (total stock at
        // cost) — without this the KPI card always rendered 0.
        inventory['costValue'],
      ]),
      lowStockCount: pickInt(<dynamic>[
        json['lowStockCount'],
        inventory['lowStockCount'],
        inventory['lowStock'],
        counts['lowStock'],
      ]),
      productCount: pickInt(<dynamic>[json['productCount'], counts['products']]),
      customerCount:
          pickInt(<dynamic>[json['customerCount'], counts['customers']]),
      supplierCount:
          pickInt(<dynamic>[json['supplierCount'], counts['suppliers']]),
      salesOrderCount: pickInt(
        <dynamic>[json['salesOrderCount'], counts['salesOrders']],
      ),
      purchaseOrderCount: pickInt(
        <dynamic>[json['purchaseOrderCount'], counts['purchaseOrders']],
      ),
      invoiceCount: pickInt(<dynamic>[
        json['invoiceCount'],
        counts['openInvoices'],
        counts['invoices'],
      ]),
      currencyCode: asStringOrNull(json['currencyCode']) ??
          asStringOrNull(settings['baseCurrencyCode']),
      topProducts:
          asMapList(json['topProducts']).map(SalesPoint.fromJson).toList(),
      salesTrend: asMapList(
        json['salesTrend'] ??
            json['salesSeries'] ??
            sales['trend'] ??
            sales['series'] ??
            json['trend'],
      ).map(SalesPoint.fromJson).toList(),
      movements: asMapList(json['recentMovements'] ?? json['movements']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'salesToday': salesToday,
        'salesThisMonth': salesThisMonth,
        'receivables': receivables,
        'inventoryValue': inventoryValue,
        'lowStockCount': lowStockCount,
        'productCount': productCount,
        'customerCount': customerCount,
        'supplierCount': supplierCount,
        'salesOrderCount': salesOrderCount,
        'purchaseOrderCount': purchaseOrderCount,
        'invoiceCount': invoiceCount,
        'currencyCode': currencyCode,
      };
}
