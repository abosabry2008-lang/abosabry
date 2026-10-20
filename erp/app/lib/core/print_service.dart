import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'formatters.dart';
import 'l10n.dart';
import 'session.dart';

/// Builds and opens the backend's printable HTML pages in an external browser.
///
/// Every printable page lives under the API base URL (which already ends with
/// `/api/v1`) and expects the access token as a `?token=` query parameter.
class PrintService {
  PrintService._();

  /// Access token of the current session, or `null` when signed out.
  static String? token(BuildContext context) =>
      context.read<Session>().api.accessToken;

  static Uri invoiceUrl(String invoiceId, String? token) =>
      _uri('/print/invoices/$invoiceId', <String, String?>{
        'token': token,
      });

  static Uri customerStatementUrl(
    String customerId,
    String? token, {
    DateTime? from,
    DateTime? to,
  }) =>
      _uri('/print/customers/$customerId/statement', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
      });

  static Uri supplierStatementUrl(
    String supplierId,
    String? token, {
    DateTime? from,
    DateTime? to,
  }) =>
      _uri('/print/suppliers/$supplierId/statement', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
      });

  static Uri salesReportUrl(
    String? token, {
    DateTime? from,
    DateTime? to,
    String? groupBy,
  }) =>
      _uri('/print/reports/sales', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
        if (groupBy != null && groupBy.isNotEmpty) 'groupBy': groupBy,
      });

  static Uri inventoryValuationUrl(String? token, {String? warehouseId}) =>
      _uri('/print/reports/inventory-valuation', <String, String?>{
        'token': token,
        if (warehouseId != null && warehouseId.isNotEmpty)
          'warehouseId': warehouseId,
      });

  static Uri topProductsUrl(
    String? token, {
    DateTime? from,
    DateTime? to,
    int? limit,
  }) =>
      _uri('/print/reports/top-products', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
        if (limit != null) 'limit': limit.toString(),
      });

  static Uri receivablesBySalespersonUrl(
    String? token, {
    DateTime? from,
    DateTime? to,
    String? userId,
  }) =>
      _uri('/print/reports/receivables-by-salesperson', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
        if (userId != null && userId.isNotEmpty) 'userId': userId,
      });

  static Uri supplierPayablesUrl(
    String? token, {
    DateTime? from,
    DateTime? to,
  }) =>
      _uri('/print/reports/supplier-payables', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
      });

  static Uri stockBalanceUrl(
    String? token, {
    String? warehouseId,
    String? categoryId,
  }) =>
      _uri('/print/reports/stock-balance', <String, String?>{
        'token': token,
        if (warehouseId != null && warehouseId.isNotEmpty)
          'warehouseId': warehouseId,
        if (categoryId != null && categoryId.isNotEmpty)
          'categoryId': categoryId,
      });

  static Uri itemMovementUrl(
    String? token, {
    required String productId,
    DateTime? from,
    DateTime? to,
    String? warehouseId,
  }) =>
      _uri('/print/reports/item-movement', <String, String?>{
        'token': token,
        'productId': productId,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
        if (warehouseId != null && warehouseId.isNotEmpty)
          'warehouseId': warehouseId,
      });

  static Uri consolidatedSalesNoteUrl(
    String? token, {
    DateTime? from,
    DateTime? to,
    String? salespersonId,
  }) =>
      _uri('/print/reports/consolidated-sales-note', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
        if (salespersonId != null && salespersonId.isNotEmpty)
          'salespersonId': salespersonId,
      });

  static Uri profitBySalespersonUrl(
    String? token, {
    DateTime? from,
    DateTime? to,
    String? salespersonId,
  }) =>
      _uri('/print/reports/profit-by-salesperson', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
        if (salespersonId != null && salespersonId.isNotEmpty)
          'salespersonId': salespersonId,
      });

  static Uri collectionsBySalespersonUrl(
    String? token, {
    DateTime? from,
    DateTime? to,
    String? salespersonId,
  }) =>
      _uri('/print/reports/collections-by-salesperson', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
        if (salespersonId != null && salespersonId.isNotEmpty)
          'salespersonId': salespersonId,
      });

  static Uri salespersonStatementUrl(
    String salespersonId,
    String? token, {
    DateTime? from,
    DateTime? to,
  }) =>
      _uri('/print/salespeople/$salespersonId/statement', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
      });

  /// URL of the full Excel backup (`GET /reports/backup`).
  static Uri backupUrl(String? token) =>
      _uri('/reports/backup', <String, String?>{'token': token});

  /// Convenience wrappers that read the token from the current [Session].
  static Future<bool> printInvoice(BuildContext context, String invoiceId) =>
      open(context, invoiceUrl(invoiceId, token(context)));

  static Future<bool> printCustomerStatement(
    BuildContext context,
    String customerId, {
    DateTime? from,
    DateTime? to,
  }) =>
      open(
        context,
        customerStatementUrl(customerId, token(context), from: from, to: to),
      );

  static Future<bool> printSupplierStatement(
    BuildContext context,
    String supplierId, {
    DateTime? from,
    DateTime? to,
  }) =>
      open(
        context,
        supplierStatementUrl(supplierId, token(context), from: from, to: to),
      );

  static Future<bool> printSalesReport(
    BuildContext context, {
    DateTime? from,
    DateTime? to,
    String? groupBy,
  }) =>
      open(
        context,
        salesReportUrl(token(context), from: from, to: to, groupBy: groupBy),
      );

  static Future<bool> printInventoryValuation(
    BuildContext context, {
    String? warehouseId,
  }) =>
      open(context, inventoryValuationUrl(token(context), warehouseId: warehouseId));

  static Future<bool> printTopProducts(
    BuildContext context, {
    DateTime? from,
    DateTime? to,
    int? limit,
  }) =>
      open(
        context,
        topProductsUrl(token(context), from: from, to: to, limit: limit),
      );

  static Future<bool> printReceivablesBySalesperson(
    BuildContext context, {
    DateTime? from,
    DateTime? to,
    String? userId,
  }) =>
      open(
        context,
        receivablesBySalespersonUrl(
          token(context),
          from: from,
          to: to,
          userId: userId,
        ),
      );

  static Future<bool> printSupplierPayables(
    BuildContext context, {
    DateTime? from,
    DateTime? to,
  }) =>
      open(
        context,
        supplierPayablesUrl(token(context), from: from, to: to),
      );

  static Future<bool> printStockBalance(
    BuildContext context, {
    String? warehouseId,
    String? categoryId,
  }) =>
      open(
        context,
        stockBalanceUrl(
          token(context),
          warehouseId: warehouseId,
          categoryId: categoryId,
        ),
      );

  static Future<bool> printItemMovement(
    BuildContext context, {
    required String productId,
    DateTime? from,
    DateTime? to,
    String? warehouseId,
  }) =>
      open(
        context,
        itemMovementUrl(
          token(context),
          productId: productId,
          from: from,
          to: to,
          warehouseId: warehouseId,
        ),
      );

  static Future<bool> printConsolidatedSalesNote(
    BuildContext context, {
    DateTime? from,
    DateTime? to,
    String? salespersonId,
  }) =>
      open(
        context,
        consolidatedSalesNoteUrl(
          token(context),
          from: from,
          to: to,
          salespersonId: salespersonId,
        ),
      );

  static Future<bool> printProfitBySalesperson(
    BuildContext context, {
    DateTime? from,
    DateTime? to,
    String? salespersonId,
  }) =>
      open(
        context,
        profitBySalespersonUrl(
          token(context),
          from: from,
          to: to,
          salespersonId: salespersonId,
        ),
      );

  static Future<bool> printCollectionsBySalesperson(
    BuildContext context, {
    DateTime? from,
    DateTime? to,
    String? salespersonId,
  }) =>
      open(
        context,
        collectionsBySalespersonUrl(
          token(context),
          from: from,
          to: to,
          salespersonId: salespersonId,
        ),
      );

  static Uri expenseReportUrl(
    String? token, {
    DateTime? from,
    DateTime? to,
  }) =>
      _uri('/print/reports/expenses', <String, String?>{
        'token': token,
        if (from != null) 'from': Formatters.isoDate(from),
        if (to != null) 'to': Formatters.isoDate(to),
      });

  static Future<bool> printExpenseReport(
    BuildContext context, {
    DateTime? from,
    DateTime? to,
  }) =>
      open(context, expenseReportUrl(token(context), from: from, to: to));

  static Future<bool> printSalespersonStatement(
    BuildContext context,
    String salespersonId, {
    DateTime? from,
    DateTime? to,
  }) =>
      open(
        context,
        salespersonStatementUrl(
          salespersonId,
          token(context),
          from: from,
          to: to,
        ),
      );

  /// Downloads the full Excel backup by opening it in an external browser.
  static Future<bool> downloadBackup(BuildContext context) =>
      open(context, backupUrl(token(context)));

  /// Opens [uri] in an external browser, showing a snackbar when it fails.
  static Future<bool> open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = context.s;
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        messenger.showSnackBar(
          SnackBar(content: Text(s.couldNotOpenPrintPage)),
        );
      }
      return launched;
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.couldNotOpenPrintPage)),
      );
      return false;
    }
  }

  static Uri _uri(String path, Map<String, String?> query) {
    final uri = Uri.parse('${AppConfig.baseUrl}$path');
    final params = <String, String>{};
    uri.queryParameters.forEach((key, value) => params[key] = value);
    query.forEach((key, value) {
      if (value == null || value.isEmpty) return;
      params[key] = value;
    });
    if (params.isEmpty) return uri;
    return uri.replace(queryParameters: params);
  }
}
