import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/api_exception.dart';
import '../models/cash_box.dart';
import '../models/dashboard_summary.dart';
import '../models/sales_point.dart';
import '../models/stock_movement.dart';
import '../core/json_utils.dart';

/// Dashboard KPIs (`GET /reports/dashboard`) plus a low-stock peek.
class DashboardController extends ChangeNotifier {
  DashboardController(this.api);

  final ApiClient api;

  DashboardSummary? summary;
  List<StockMovement> recentMovements = <StockMovement>[];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.getObject(
        '/reports/dashboard',
        query: <String, dynamic>{
          'tzOffset': DateTime.now().timeZoneOffset.inMinutes,
        },
      );
      summary = DashboardSummary.fromJson(data);
      recentMovements = asMapList(data['recentMovements'] ?? data['movements'])
          .map(StockMovement.fromJson)
          .toList();
    } on ApiException catch (exception) {
      error = exception.message;
    } catch (exception) {
      debugPrint('DashboardController.load failed: $exception');
      error = 'Could not load the dashboard.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// `GET /inventory/low-stock` – used by the dashboard low-stock card.
  Future<List<Map<String, dynamic>>> loadLowStock() async {
    final json = await api.get('/inventory/low-stock');
    final data = asMap(json)['data'];
    if (data is List) return asMapList(data);
    if (data is Map) return asMapList(asMap(data)['items']);
    return <Map<String, dynamic>>[];
  }
}

/// Report data for the reports screen.
class ReportsController extends ChangeNotifier {
  ReportsController(this.api);

  final ApiClient api;

  DashboardSummary? dashboard;
  bool loadingDashboard = false;
  String? dashboardError;

  List<SalesPoint> salesSeries = <SalesPoint>[];
  bool loadingSales = false;
  String? salesError;

  Map<String, dynamic> valuation = <String, dynamic>{};
  bool loadingValuation = false;
  String? valuationError;

  List<SalesPoint> topProducts = <SalesPoint>[];
  bool loadingTopProducts = false;
  String? topProductsError;

  List<Map<String, dynamic>> customerBalances = <Map<String, dynamic>>[];
  bool loadingCustomerBalances = false;
  String? customerBalancesError;

  List<Map<String, dynamic>> supplierBalances = <Map<String, dynamic>>[];
  bool loadingSupplierBalances = false;
  String? supplierBalancesError;

  List<Map<String, dynamic>> receivables = <Map<String, dynamic>>[];
  Map<String, dynamic> receivablesTotals = <String, dynamic>{};
  bool loadingReceivables = false;
  String? receivablesError;

  List<Map<String, dynamic>> supplierPayables = <Map<String, dynamic>>[];
  Map<String, dynamic> supplierPayablesTotals = <String, dynamic>{};
  bool loadingSupplierPayables = false;
  String? supplierPayablesError;

  List<Map<String, dynamic>> stockBalance = <Map<String, dynamic>>[];
  Map<String, dynamic> stockBalanceTotals = <String, dynamic>{};
  bool loadingStockBalance = false;
  String? stockBalanceError;

  Map<String, dynamic> itemMovement = <String, dynamic>{};
  bool loadingItemMovement = false;
  String? itemMovementError;

  // --- extended report suite (branch tree) -----------------------------------

  Map<String, dynamic> purchasesReport = <String, dynamic>{};
  bool loadingPurchasesReport = false;
  String? purchasesReportError;

  Map<String, dynamic> profitReport = <String, dynamic>{};
  bool loadingProfitReport = false;
  String? profitReportError;

  Map<String, dynamic> taxReport = <String, dynamic>{};
  bool loadingTaxReport = false;
  String? taxReportError;

  Map<String, dynamic> receivablesAging = <String, dynamic>{};
  bool loadingReceivablesAging = false;
  String? receivablesAgingError;

  Map<String, dynamic> payablesAging = <String, dynamic>{};
  bool loadingPayablesAging = false;
  String? payablesAgingError;

  List<Map<String, dynamic>> lowStock = <Map<String, dynamic>>[];
  bool loadingLowStock = false;
  String? lowStockError;

  List<Map<String, dynamic>> shortages = <Map<String, dynamic>>[];
  Map<String, dynamic> shortagesTotals = <String, dynamic>{};
  bool loadingShortages = false;
  String? shortagesError;

  List<Map<String, dynamic>> orderFulfilment = <Map<String, dynamic>>[];
  Map<String, dynamic> orderFulfilmentTotals = <String, dynamic>{};
  bool loadingOrderFulfilment = false;
  String? orderFulfilmentError;

  List<CashBox> boxes = <CashBox>[];
  bool loadingBoxes = false;
  String? boxesError;

  Map<String, dynamic> expenseReport = <String, dynamic>{};
  bool loadingExpenseReport = false;
  String? expenseReportError;

  Map<String, dynamic> trialBalanceReport = <String, dynamic>{};
  bool loadingTrialBalance = false;
  String? trialBalanceError;

  Map<String, dynamic> incomeStatement = <String, dynamic>{};
  bool loadingIncomeStatement = false;
  String? incomeStatementError;

  Map<String, dynamic> balanceSheet = <String, dynamic>{};
  bool loadingBalanceSheet = false;
  String? balanceSheetError;

  Map<String, dynamic> consolidatedSalesNote = <String, dynamic>{};
  bool loadingConsolidatedSalesNote = false;
  String? consolidatedSalesNoteError;

  Map<String, dynamic> profitBySalesperson = <String, dynamic>{};
  bool loadingProfitBySalesperson = false;
  String? profitBySalespersonError;

  Map<String, dynamic> collectionsBySalesperson = <String, dynamic>{};
  bool loadingCollectionsBySalesperson = false;
  String? collectionsBySalespersonError;

  Map<String, dynamic> salespersonStatement = <String, dynamic>{};
  bool loadingSalespersonStatement = false;
  String? salespersonStatementError;

  Map<String, dynamic> salespersonCustomerDebt = <String, dynamic>{};
  bool loadingSalespersonCustomerDebt = false;
  String? salespersonCustomerDebtError;

  Future<void> loadDashboard() async {
    loadingDashboard = true;
    dashboardError = null;
    notifyListeners();
    try {
      dashboard = DashboardSummary.fromJson(
        await api.getObject(
          '/reports/dashboard',
          query: <String, dynamic>{
            'tzOffset': DateTime.now().timeZoneOffset.inMinutes,
          },
        ),
      );
    } on ApiException catch (exception) {
      dashboardError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadDashboard failed: $exception');
      dashboardError = 'Could not load the dashboard report.';
    } finally {
      loadingDashboard = false;
      notifyListeners();
    }
  }

  Future<void> loadSales({
    DateTime? from,
    DateTime? to,
    String groupBy = 'day',
  }) async {
    loadingSales = true;
    salesError = null;
    notifyListeners();
    try {
      final rows = await _fetchRows(
        '/reports/sales',
        <String, dynamic>{
          if (from != null || to != null) 'groupBy': groupBy,
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
        },
        listKey: 'series',
      );
      salesSeries = rows.map(SalesPoint.fromJson).toList();
    } on ApiException catch (exception) {
      salesError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadSales failed: $exception');
      salesError = 'Could not load the sales report.';
    } finally {
      loadingSales = false;
      notifyListeners();
    }
  }

  Future<void> loadValuation() async {
    loadingValuation = true;
    valuationError = null;
    notifyListeners();
    try {
      final json = await api.get('/reports/inventory-valuation');
      final data = asMap(json)['data'];
      if (data is Map) {
        valuation = asMap(data);
      } else if (data is List) {
        valuation = <String, dynamic>{'items': asMapList(data)};
      } else {
        valuation = <String, dynamic>{};
      }
    } on ApiException catch (exception) {
      valuationError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadValuation failed: $exception');
      valuationError = 'Could not load the inventory valuation.';
    } finally {
      loadingValuation = false;
      notifyListeners();
    }
  }

  Future<void> loadTopProducts({
    DateTime? from,
    DateTime? to,
    int limit = 10,
  }) async {
    loadingTopProducts = true;
    topProductsError = null;
    notifyListeners();
    try {
      final rows = await _fetchRows(
        '/reports/top-products',
        <String, dynamic>{
          'limit': limit,
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
        },
        listKey: 'rows',
      );
      topProducts = rows.map(SalesPoint.fromJson).toList();
    } on ApiException catch (exception) {
      topProductsError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadTopProducts failed: $exception');
      topProductsError = 'Could not load top products.';
    } finally {
      loadingTopProducts = false;
      notifyListeners();
    }
  }

  Future<void> loadCustomerBalances({String? salespersonId}) async {
    loadingCustomerBalances = true;
    customerBalancesError = null;
    notifyListeners();
    try {
      customerBalances = await _fetchRows(
        '/reports/customer-balances',
        <String, dynamic>{
          if (salespersonId != null && salespersonId.isNotEmpty)
            'salespersonId': salespersonId,
        },
      );
    } on ApiException catch (exception) {
      customerBalancesError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadCustomerBalances failed: $exception');
      customerBalancesError = 'Could not load customer balances.';
    } finally {
      loadingCustomerBalances = false;
      notifyListeners();
    }
  }

  Future<void> loadSupplierBalances() async {
    loadingSupplierBalances = true;
    supplierBalancesError = null;
    notifyListeners();
    try {
      supplierBalances = await _fetchRows('/reports/supplier-balances', null);
    } on ApiException catch (exception) {
      supplierBalancesError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadSupplierBalances failed: $exception');
      supplierBalancesError = 'Could not load supplier balances.';
    } finally {
      loadingSupplierBalances = false;
      notifyListeners();
    }
  }

  Future<void> loadReceivables({
    DateTime? from,
    DateTime? to,
    String? userId,
  }) async {
    loadingReceivables = true;
    receivablesError = null;
    notifyListeners();
    try {
      final data = await _fetchReport(
        '/reports/receivables-by-salesperson',
        <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
          if (userId != null && userId.isNotEmpty) 'userId': userId,
        },
      );
      receivables = asMapList(data['rows']);
      receivablesTotals = asMap(data['totals']);
    } on ApiException catch (exception) {
      receivablesError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadReceivables failed: $exception');
      receivablesError = 'Could not load receivables by salesperson.';
    } finally {
      loadingReceivables = false;
      notifyListeners();
    }
  }

  Future<void> loadSupplierPayables({DateTime? from, DateTime? to}) async {
    loadingSupplierPayables = true;
    supplierPayablesError = null;
    notifyListeners();
    try {
      final data = await _fetchReport(
        '/reports/supplier-payables',
        <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
        },
      );
      supplierPayables = asMapList(data['rows']);
      supplierPayablesTotals = asMap(data['totals']);
    } on ApiException catch (exception) {
      supplierPayablesError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadSupplierPayables failed: $exception');
      supplierPayablesError = 'Could not load supplier payables.';
    } finally {
      loadingSupplierPayables = false;
      notifyListeners();
    }
  }

  Future<void> loadStockBalance({
    String? warehouseId,
    String? categoryId,
  }) async {
    loadingStockBalance = true;
    stockBalanceError = null;
    notifyListeners();
    try {
      final data = await _fetchReport(
        '/reports/stock-balance',
        <String, dynamic>{
          if (warehouseId != null && warehouseId.isNotEmpty)
            'warehouseId': warehouseId,
          if (categoryId != null && categoryId.isNotEmpty)
            'categoryId': categoryId,
        },
      );
      stockBalance = asMapList(data['rows']);
      stockBalanceTotals = asMap(data['totals']);
    } on ApiException catch (exception) {
      stockBalanceError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadStockBalance failed: $exception');
      stockBalanceError = 'Could not load the stock balance.';
    } finally {
      loadingStockBalance = false;
      notifyListeners();
    }
  }

  Future<void> loadItemMovement({
    required String productId,
    DateTime? from,
    DateTime? to,
    String? warehouseId,
  }) async {
    loadingItemMovement = true;
    itemMovementError = null;
    notifyListeners();
    try {
      itemMovement = await _fetchReport(
        '/reports/item-movement',
        <String, dynamic>{
          'productId': productId,
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
          if (warehouseId != null && warehouseId.isNotEmpty)
            'warehouseId': warehouseId,
        },
      );
    } on ApiException catch (exception) {
      itemMovementError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadItemMovement failed: $exception');
      itemMovementError = 'Could not load the item movement.';
    } finally {
      loadingItemMovement = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Extended reports
  // ---------------------------------------------------------------------------

  Future<void> loadPurchasesReport({
    DateTime? from,
    DateTime? to,
    String groupBy = 'day',
  }) =>
      _loadSection(
        path: '/reports/purchases',
        query: <String, dynamic>{
          'groupBy': groupBy,
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
        },
        setStatus: (loading, error) {
          loadingPurchasesReport = loading;
          purchasesReportError = error;
        },
        setData: (data) => purchasesReport = data,
        errorMessage: 'Could not load the purchases report',
      );

  Future<void> loadProfitReport({DateTime? from, DateTime? to}) => _loadSection(
        path: '/reports/profit',
        query: <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
        },
        setStatus: (loading, error) {
          loadingProfitReport = loading;
          profitReportError = error;
        },
        setData: (data) => profitReport = data,
        errorMessage: 'Could not load the sales profit report',
      );

  Future<void> loadTaxReport({DateTime? from, DateTime? to}) => _loadSection(
        path: '/reports/tax',
        query: <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
        },
        setStatus: (loading, error) {
          loadingTaxReport = loading;
          taxReportError = error;
        },
        setData: (data) => taxReport = data,
        errorMessage: 'Could not load the tax report',
      );

  Future<void> loadReceivablesAging({DateTime? asOf}) => _loadSection(
        path: '/reports/aging',
        query: <String, dynamic>{
          'side': 'receivable',
          if (asOf != null) 'asOf': Formatters.isoRangeEnd(asOf),
        },
        setStatus: (loading, error) {
          loadingReceivablesAging = loading;
          receivablesAgingError = error;
        },
        setData: (data) => receivablesAging = data,
        errorMessage: 'Could not load the receivables aging report',
      );

  Future<void> loadPayablesAging({DateTime? asOf}) => _loadSection(
        path: '/reports/aging',
        query: <String, dynamic>{
          'side': 'payable',
          if (asOf != null) 'asOf': Formatters.isoRangeEnd(asOf),
        },
        setStatus: (loading, error) {
          loadingPayablesAging = loading;
          payablesAgingError = error;
        },
        setData: (data) => payablesAging = data,
        errorMessage: 'Could not load the payables aging report',
      );

  Future<void> loadLowStockReport({String? warehouseId}) async {
    loadingLowStock = true;
    lowStockError = null;
    notifyListeners();
    try {
      final json = await api.get(
        '/reports/low-stock',
        query: <String, dynamic>{
          if (warehouseId != null && warehouseId.isNotEmpty)
            'warehouseId': warehouseId,
        },
      );
      final data = asMap(json)['data'];
      lowStock = data is List
          ? asMapList(data)
          : asMapList(asMap(data)['items']);
    } on ApiException catch (exception) {
      lowStockError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadLowStockReport failed: $exception');
      lowStockError = 'Could not load the low stock report.';
    } finally {
      loadingLowStock = false;
      notifyListeners();
    }
  }

  Future<void> loadShortagesReport({String? warehouseId}) async {
    loadingShortages = true;
    shortagesError = null;
    notifyListeners();
    try {
      final data = await _fetchReport(
        '/reports/shortages',
        <String, dynamic>{
          if (warehouseId != null && warehouseId.isNotEmpty)
            'warehouseId': warehouseId,
        },
      );
      shortages = asMapList(data['rows']);
      shortagesTotals = asMap(data['totals']);
    } on ApiException catch (exception) {
      shortagesError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadShortagesReport failed: $exception');
      shortagesError = 'Could not load the shortages report.';
    } finally {
      loadingShortages = false;
      notifyListeners();
    }
  }

  Future<void> loadOrderFulfilmentReport({String? warehouseId}) async {
    loadingOrderFulfilment = true;
    orderFulfilmentError = null;
    notifyListeners();
    try {
      final data = await _fetchReport(
        '/reports/order-fulfilment',
        <String, dynamic>{
          if (warehouseId != null && warehouseId.isNotEmpty)
            'warehouseId': warehouseId,
        },
      );
      orderFulfilment = asMapList(data['rows']);
      orderFulfilmentTotals = asMap(data['totals']);
    } on ApiException catch (exception) {
      orderFulfilmentError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadOrderFulfilmentReport failed: $exception');
      orderFulfilmentError = 'Could not load the order fulfilment report.';
    } finally {
      loadingOrderFulfilment = false;
      notifyListeners();
    }
  }

  Future<void> loadBoxes() async {
    loadingBoxes = true;
    boxesError = null;
    notifyListeners();
    try {
      final json = await api.get('/treasury/boxes');
      final data = asMap(json)['data'];
      boxes = (data is List
              ? asMapList(data)
              : asMapList(asMap(data)['items']))
          .map(CashBox.fromJson)
          .toList();
    } on ApiException catch (exception) {
      boxesError = exception.message;
    } catch (exception) {
      debugPrint('ReportsController.loadBoxes failed: $exception');
      boxesError = 'Could not load the cash boxes.';
    } finally {
      loadingBoxes = false;
      notifyListeners();
    }
  }

  Future<void> loadExpenseReport({DateTime? from, DateTime? to}) => _loadSection(
        path: '/expenses/report',
        query: <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
        },
        setStatus: (loading, error) {
          loadingExpenseReport = loading;
          expenseReportError = error;
        },
        setData: (data) => expenseReport = data,
        errorMessage: 'Could not load the expense report',
      );

  Future<void> loadTrialBalance() => _loadSection(
        path: '/accounting/trial-balance',
        setStatus: (loading, error) {
          loadingTrialBalance = loading;
          trialBalanceError = error;
        },
        setData: (data) => trialBalanceReport = data,
        errorMessage: 'Could not load the trial balance',
      );

  Future<void> loadIncomeStatement({DateTime? from, DateTime? to}) =>
      _loadSection(
        path: '/accounting/income-statement',
        query: <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
        },
        setStatus: (loading, error) {
          loadingIncomeStatement = loading;
          incomeStatementError = error;
        },
        setData: (data) => incomeStatement = data,
        errorMessage: 'Could not load the income statement',
      );

  Future<void> loadBalanceSheet({DateTime? asOf}) => _loadSection(
        path: '/accounting/balance-sheet',
        query: <String, dynamic>{
          if (asOf != null) 'asOf': Formatters.isoRangeEnd(asOf),
        },
        setStatus: (loading, error) {
          loadingBalanceSheet = loading;
          balanceSheetError = error;
        },
        setData: (data) => balanceSheet = data,
        errorMessage: 'Could not load the balance sheet',
      );

  // --- salespeople reports (تقارير المناديب) --------------------------------

  Future<void> loadConsolidatedSalesNote({
    DateTime? from,
    DateTime? to,
    String? salespersonId,
  }) =>
      _loadSection(
        path: '/reports/consolidated-sales-note',
        query: <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
          if (salespersonId != null && salespersonId.isNotEmpty)
            'salespersonId': salespersonId,
        },
        setStatus: (loading, error) {
          loadingConsolidatedSalesNote = loading;
          consolidatedSalesNoteError = error;
        },
        setData: (data) => consolidatedSalesNote = data,
        errorMessage: 'Could not load the consolidated sales note',
      );

  Future<void> loadProfitBySalesperson({
    DateTime? from,
    DateTime? to,
    String? salespersonId,
  }) =>
      _loadSection(
        path: '/reports/profit-by-salesperson',
        query: <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
          if (salespersonId != null && salespersonId.isNotEmpty)
            'salespersonId': salespersonId,
        },
        setStatus: (loading, error) {
          loadingProfitBySalesperson = loading;
          profitBySalespersonError = error;
        },
        setData: (data) => profitBySalesperson = data,
        errorMessage: 'Could not load the salesperson profitability',
      );

  Future<void> loadCollectionsBySalesperson({
    DateTime? from,
    DateTime? to,
    String? salespersonId,
  }) =>
      _loadSection(
        path: '/reports/collections-by-salesperson',
        query: <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
          if (salespersonId != null && salespersonId.isNotEmpty)
            'salespersonId': salespersonId,
        },
        setStatus: (loading, error) {
          loadingCollectionsBySalesperson = loading;
          collectionsBySalespersonError = error;
        },
        setData: (data) => collectionsBySalesperson = data,
        errorMessage: 'Could not load the salesperson collections',
      );

  Future<void> loadSalespersonStatement({
    required String salespersonId,
    DateTime? from,
    DateTime? to,
  }) =>
      _loadSection(
        path: '/reports/salespeople/$salespersonId/statement',
        query: <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
        },
        setStatus: (loading, error) {
          loadingSalespersonStatement = loading;
          salespersonStatementError = error;
        },
        setData: (data) => salespersonStatement = data,
        errorMessage: 'Could not load the salesperson statement',
      );

  Future<void> loadSalespersonCustomerDebt({
    required String salespersonId,
    DateTime? from,
    DateTime? to,
    String filter = 'all',
  }) =>
      _loadSection(
        path: '/reports/salespeople/$salespersonId/customers',
        query: <String, dynamic>{
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': Formatters.isoRangeEnd(to),
          'filter': filter,
        },
        setStatus: (loading, error) {
          loadingSalespersonCustomerDebt = loading;
          salespersonCustomerDebtError = error;
        },
        setData: (data) => salespersonCustomerDebt = data,
        errorMessage: 'Could not load the salesperson customer debt',
      );

  /// Shared loader for reports whose `data` is an object.
  Future<void> _loadSection({
    required String path,
    Map<String, dynamic>? query,
    required void Function(bool loading, String? error) setStatus,
    required void Function(Map<String, dynamic> data) setData,
    required String errorMessage,
  }) async {
    setStatus(true, null);
    notifyListeners();
    try {
      setData(await _fetchReport(path, query));
      setStatus(false, null);
    } on ApiException catch (exception) {
      setStatus(false, exception.message);
    } catch (exception) {
      debugPrint('ReportsController._loadSection($path) failed: $exception');
      setStatus(false, '$errorMessage.');
    } finally {
      notifyListeners();
    }
  }

  /// Fetches a report whose `data` is an object (e.g. `{rows, totals}`).
  Future<Map<String, dynamic>> _fetchReport(
    String path,
    Map<String, dynamic>? query,
  ) async {
    final json = await api.get(path, query: query);
    return asMap(asMap(json)['data']);
  }

  /// Normalises `{data: [...]}`, `{data: {items: [...]}}` and single objects.
  Future<List<Map<String, dynamic>>> _fetchRows(
    String path,
    Map<String, dynamic>? query, {
    String? listKey,
  }) async {
    final json = await api.get(path, query: query);
    final data = asMap(json)['data'];
    if (data is List) return asMapList(data);
    if (data is Map) {
      final map = asMap(data);
      if (listKey != null && map[listKey] is List) {
        return asMapList(map[listKey]);
      }
      final items = map['items'];
      if (items is List) return asMapList(items);
      return <Map<String, dynamic>>[map];
    }
    return <Map<String, dynamic>>[];
  }
}
