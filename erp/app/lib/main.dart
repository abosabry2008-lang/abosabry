import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/config.dart';
import 'core/l10n.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/app_shell.dart';
import 'state/accounting_controller.dart';
import 'state/categories_controller.dart';
import 'state/collections_controller.dart';
import 'state/currencies_controller.dart';
import 'state/customers_controller.dart';
import 'state/expenses_controller.dart';
import 'state/inventory_controller.dart';
import 'state/invoices_controller.dart';
import 'state/opening_balances_controller.dart';
import 'state/payments_controller.dart';
import 'state/pos_controller.dart';
import 'state/product_catalog.dart';
import 'state/products_controller.dart';
import 'state/purchase_orders_controller.dart';
import 'state/reports_controller.dart';
import 'state/returns_controller.dart';
import 'state/sales_orders_controller.dart';
import 'state/salespeople_controller.dart';
import 'state/settings_controller.dart';
import 'state/settlements_controller.dart';
import 'state/suppliers_controller.dart';
import 'state/transfers_controller.dart';
import 'state/users_controller.dart';
import 'state/warehouses_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ErpApp());
}

/// Root widget: owns the [ApiClient], the [Session] and every feature
/// controller, and switches between the splash, login and shell based on the
/// session status.
class ErpApp extends StatefulWidget {
  const ErpApp({super.key});

  @override
  State<ErpApp> createState() => _ErpAppState();
}

class _ErpAppState extends State<ErpApp> {
  late final ApiClient _api;
  late final Session _session;
  late final LocaleController _locale;

  late final CategoriesController _categories;
  late final ProductsController _products;
  late final ProductCatalog _catalog;
  late final WarehousesController _warehouses;
  late final StockController _stock;
  late final MovementsController _movements;
  late final SuppliersController _suppliers;
  late final CustomersController _customers;
  late final CurrenciesController _currencies;
  late final UsersController _users;
  late final InvoicesController _invoices;
  late final PaymentsController _payments;
  late final CollectionVouchersController _collections;
  late final TransfersController _transfers;
  late final ExpensesController _expenses;
  late final SettlementsController _settlements;
  late final PurchaseOrdersController _purchaseOrders;
  late final SalesOrdersController _salesOrders;
  late final ReturnsController _returns;
  late final AccountsController _accounts;
  late final JournalController _journal;
  late final OpeningBalancesController _openingBalances;
  late final SettingsController _settings;
  late final DashboardController _dashboard;
  late final ReportsController _reports;
  late final SalespeopleController _salespeople;
  late final PosController _pos;

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _session = Session(client: _api);
    _locale = LocaleController();

    _categories = CategoriesController(_api);
    _products = ProductsController(_api);
    _catalog = ProductCatalog(_api);
    _warehouses = WarehousesController(_api);
    _stock = StockController(_api);
    _movements = MovementsController(_api);
    _suppliers = SuppliersController(_api);
    _customers = CustomersController(_api);
    _currencies = CurrenciesController(_api);
    _users = UsersController(_api);
    _invoices = InvoicesController(_api);
    _payments = PaymentsController(_api);
    _collections = CollectionVouchersController(_api);
    _transfers = TransfersController(_api);
    _expenses = ExpensesController(_api);
    _settlements = SettlementsController(_api);
    _purchaseOrders = PurchaseOrdersController(_api);
    _salesOrders = SalesOrdersController(_api);
    _returns = ReturnsController(_api);
    _accounts = AccountsController(_api);
    _journal = JournalController(_api);
    _openingBalances = OpeningBalancesController(_api);
    _settings = SettingsController(_api);
    _dashboard = DashboardController(_api);
    _reports = ReportsController(_api);
    _salespeople = SalespeopleController(_api);
    _pos = PosController(_api);

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await AppConfig.load();
    await _locale.load();
    await _session.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: _session),
        ChangeNotifierProvider<LocaleController>.value(value: _locale),
        ChangeNotifierProvider<CategoriesController>.value(value: _categories),
        ChangeNotifierProvider<ProductsController>.value(value: _products),
        ChangeNotifierProvider<ProductCatalog>.value(value: _catalog),
        ChangeNotifierProvider<WarehousesController>.value(value: _warehouses),
        ChangeNotifierProvider<StockController>.value(value: _stock),
        ChangeNotifierProvider<MovementsController>.value(value: _movements),
        ChangeNotifierProvider<SuppliersController>.value(value: _suppliers),
        ChangeNotifierProvider<CustomersController>.value(value: _customers),
        ChangeNotifierProvider<CurrenciesController>.value(value: _currencies),
        ChangeNotifierProvider<UsersController>.value(value: _users),
        ChangeNotifierProvider<InvoicesController>.value(value: _invoices),
        ChangeNotifierProvider<PaymentsController>.value(value: _payments),
        ChangeNotifierProvider<CollectionVouchersController>.value(
          value: _collections,
        ),
        ChangeNotifierProvider<TransfersController>.value(value: _transfers),
        ChangeNotifierProvider<ExpensesController>.value(value: _expenses),
        ChangeNotifierProvider<SettlementsController>.value(value: _settlements),
        ChangeNotifierProvider<PurchaseOrdersController>.value(
          value: _purchaseOrders,
        ),
        ChangeNotifierProvider<SalesOrdersController>.value(
          value: _salesOrders,
        ),
        ChangeNotifierProvider<ReturnsController>.value(value: _returns),
        ChangeNotifierProvider<AccountsController>.value(value: _accounts),
        ChangeNotifierProvider<JournalController>.value(value: _journal),
        ChangeNotifierProvider<OpeningBalancesController>.value(
          value: _openingBalances,
        ),
        ChangeNotifierProvider<SettingsController>.value(value: _settings),
        ChangeNotifierProvider<DashboardController>.value(value: _dashboard),
        ChangeNotifierProvider<ReportsController>.value(value: _reports),
        ChangeNotifierProvider<SalespeopleController>.value(value: _salespeople),
        ChangeNotifierProvider<PosController>.value(value: _pos),
      ],
      child: Consumer<LocaleController>(
        builder: (context, localeController, _) {
          // Keep the API client's language in sync so server error messages are
          // shown in the active language.
          _api.locale = localeController.locale;
          return MaterialApp(
          title: 'ERP',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          locale: localeController.locale,
          supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            appStringsDelegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const _SessionGate(),
        );
        },
      ),
    );
  }
}

/// Picks the correct root screen for the current [SessionStatus].
class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    final status = context.select<Session, SessionStatus>(
      (session) => session.status,
    );
    switch (status) {
      case SessionStatus.unknown:
        return const _SplashScreen();
      case SessionStatus.unauthenticated:
        return const LoginScreen();
      case SessionStatus.authenticated:
        return const AppShell();
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.inventory_2_outlined, size: 56),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
