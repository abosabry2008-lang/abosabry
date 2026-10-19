import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../state/settings_controller.dart';
import '../accounting/accounts_screen.dart';
import '../accounting/journal_screen.dart';
import '../categories/categories_screen.dart';
import '../customers/customers_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../inventory/inventory_screen.dart';
import '../inventory/movements_screen.dart';
import '../invoices/invoices_screen.dart';
import '../treasury/treasury_screen.dart';
import '../products/products_screen.dart';
import '../purchasing/purchase_orders_screen.dart';
import '../reports/reports_screen.dart';
import '../returns/returns_screen.dart';
import '../sales/sales_orders_screen.dart';
import '../settings/settings_screen.dart';
import '../suppliers/suppliers_screen.dart';
import '../warehouses/warehouses_screen.dart';
import 'navigation.dart';

/// A navigation entry guarded by a permission key.
class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.permission,
    required this.builder,
    this.alternatePermission,
  });

  final String Function(AppStrings) label;
  final IconData icon;
  final String permission;
  final Widget Function() builder;

  /// Optional second permission that also grants access (e.g. Returns are
  /// reachable with either `sales` or `purchases`).
  final String? alternatePermission;
}

final List<_Destination> _destinations = <_Destination>[
  _Destination(
    label: (s) => s.dashboard,
    icon: Icons.dashboard_outlined,
    permission: 'dashboard',
    builder: _dashboard,
  ),
  // نقطة البيع مخفية مؤقتاً — يمكن إعادتها بفك التعليق عن هذا السطر.
  // _Destination(
  //   label: (s) => s.pointOfSale,
  //   icon: Icons.point_of_sale_outlined,
  //   permission: 'pos',
  //   builder: _pos,
  // ),
  _Destination(
    label: (s) => s.products,
    icon: Icons.inventory_2_outlined,
    permission: 'products',
    builder: _products,
  ),
  _Destination(
    label: (s) => s.categories,
    icon: Icons.category_outlined,
    permission: 'categories',
    builder: _categories,
  ),
  _Destination(
    label: (s) => s.inventory,
    icon: Icons.warehouse_outlined,
    permission: 'inventory',
    builder: _inventory,
  ),
  _Destination(
    label: (s) => s.movements,
    icon: Icons.swap_vert,
    permission: 'inventory',
    builder: _movements,
  ),
  _Destination(
    label: (s) => s.warehouses,
    icon: Icons.store_mall_directory_outlined,
    permission: 'warehouses',
    builder: _warehouses,
  ),
  _Destination(
    label: (s) => s.suppliers,
    icon: Icons.local_shipping_outlined,
    permission: 'suppliers',
    builder: _suppliers,
  ),
  _Destination(
    label: (s) => s.purchasing,
    icon: Icons.shopping_cart_outlined,
    permission: 'purchases',
    builder: _purchases,
  ),
  _Destination(
    label: (s) => s.customers,
    icon: Icons.people_outline,
    permission: 'customers',
    builder: _customers,
  ),
  _Destination(
    label: (s) => s.salesOrders,
    icon: Icons.receipt_long_outlined,
    permission: 'sales',
    builder: _salesOrders,
  ),
  _Destination(
    label: (s) => s.returns,
    icon: Icons.keyboard_return_outlined,
    permission: 'sales',
    alternatePermission: 'purchases',
    builder: _returns,
  ),
  _Destination(
    label: (s) => s.invoices,
    icon: Icons.description_outlined,
    permission: 'invoices',
    builder: _invoices,
  ),
  _Destination(
    label: (s) => s.treasury,
    icon: Icons.account_balance_wallet_outlined,
    permission: 'treasury',
    builder: _treasury,
  ),
  _Destination(
    label: (s) => s.reports,
    icon: Icons.insights_outlined,
    permission: 'reports',
    builder: _reports,
  ),
  _Destination(
    label: (s) => s.accounts,
    icon: Icons.account_balance_outlined,
    permission: 'accounting',
    builder: _accounts,
  ),
  _Destination(
    label: (s) => s.journal,
    icon: Icons.menu_book_outlined,
    permission: 'accounting',
    builder: _journal,
  ),
  // الإعدادات انتقلت إلى شريط الأعلى بجانب زر تغيير اللغة،
  // والمستخدمون أصبحوا تبويبًا داخل الإعدادات (للمسؤول فقط).
];

Widget _dashboard() => const DashboardScreen();
// Widget _pos() => const PosScreen(); // نقطة البيع مخفية مؤقتاً
Widget _products() => const ProductsScreen();
Widget _categories() => const CategoriesScreen();
Widget _inventory() => const InventoryScreen();
Widget _movements() => const MovementsScreen();
Widget _warehouses() => const WarehousesScreen();
Widget _suppliers() => const SuppliersScreen();
Widget _purchases() => const PurchaseOrdersScreen();
Widget _customers() => const CustomersScreen();
Widget _salesOrders() => const SalesOrdersScreen();
Widget _returns() => const ReturnsScreen();
Widget _invoices() => const InvoicesScreen();
Widget _treasury() => const TreasuryScreen();
Widget _reports() => const ReportsScreen();
Widget _accounts() => const AccountsScreen();
Widget _journal() => const JournalScreen();
// Widget _settings() => const SettingsScreen(); // الإعدادات في شريط الأعلى الآن

/// Responsive application shell: a [NavigationRail] on wide layouts and a
/// [NavigationDrawer] on narrow ones. The AppBar shows the signed-in user,
/// their role and a logout action.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    final settings = context.read<SettingsController>();
    if (settings.settings == null) {
      settings.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = context.watch<Session>();
    final destinations = _destinations
        .where(
          (destination) =>
              session.can(destination.permission) ||
              (destination.alternatePermission != null &&
                  session.can(destination.alternatePermission!)),
        )
        .toList();

    if (destinations.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(s.appName),
          actions: <Widget>[
            if (session.can('settings')) const _SettingsButton(),
            const _LanguageButton(),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              s.noAccessMessage(s.status(session.role)),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final index = _index.clamp(0, destinations.length - 1);
    final destination = destinations[index];
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
    final isExtraWide = width >= 1280;

    return Scaffold(
      appBar: AppBar(
        title: Text(destination.label(s)),
        actions: <Widget>[
          if (session.can('settings')) const _SettingsButton(),
          const _LanguageButton(),
          _UserMenu(session: session),
          const SizedBox(width: 8),
        ],
      ),
      drawer: isWide
          ? null
          : NavigationDrawer(
              selectedIndex: index,
              onDestinationSelected: (value) {
                Navigator.of(context).pop();
                setState(() => _index = value);
              },
              children: <Widget>[
                _DrawerHeader(session: session),
                for (final item in destinations)
                  NavigationDrawerDestination(
                    icon: Icon(item.icon),
                    label: Text(item.label(s)),
                  ),
                const SizedBox(height: 8),
              ],
            ),
      body: Row(
        children: <Widget>[
          if (isWide)
            NavigationRail(
              selectedIndex: index,
              extended: isExtraWide,
              labelType: isExtraWide ? null : NavigationRailLabelType.all,
              onDestinationSelected: (value) =>
                  setState(() => _index = value),
              destinations: <NavigationRailDestination>[
                for (final item in destinations)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    label: Text(item.label(s)),
                  ),
              ],
            ),
          if (isWide) const VerticalDivider(width: 1),
          Expanded(child: destination.builder()),
        ],
      ),
    );
  }
}

/// AppBar action that opens the settings screen (next to the language button).
class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: context.s.settings,
      onPressed: () => pushScreen(
        context,
        context.s.settings,
        const SettingsScreen(),
      ),
    );
  }
}

/// AppBar action that toggles between English and Arabic.
class _LanguageButton extends StatelessWidget {
  const _LanguageButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.translate),
      tooltip: context.s.switchLanguageTooltip,
      onPressed: () => context.read<LocaleController>().toggle(),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            session.user?.name ?? context.s.erpUser,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            context.s.status(session.role),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = session.user;
    return PopupMenuButton<String>(
      tooltip: context.s.account,
      onSelected: (value) {
        if (value == 'logout') {
          context.read<Session>().logout();
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                user?.name ?? context.s.erpUser,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                user?.email ?? '',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 6),
              Text(
                context.s.roleLabel(context.s.status(user?.role)),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: Text(context.s.signOut),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                _initials(user?.name),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  user?.name ?? context.s.erpUser,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  context.s.status(user?.role),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  String _initials(String? name) {
    final text = (name ?? '').trim();
    if (text.isEmpty) return '?';
    final parts = text.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
