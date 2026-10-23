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
import '../opening_balances/opening_balances_screen.dart';
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

enum _NavGroup { main, sales, purchasing, inventory, treasury, accounting, reports }

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

_NavGroup _groupFor(_Destination destination) {
  switch (destination.permission) {
    case 'dashboard':
      return _NavGroup.main;
    case 'customers':
    case 'sales':
    case 'invoices':
      return _NavGroup.sales;
    case 'suppliers':
    case 'purchases':
      return _NavGroup.purchasing;
    case 'products':
    case 'categories':
    case 'inventory':
    case 'warehouses':
      return _NavGroup.inventory;
    case 'treasury':
      return _NavGroup.treasury;
    case 'accounting':
    case 'openingBalances':
      return _NavGroup.accounting;
    default:
      return _NavGroup.reports;
  }
}

int _groupRank(_NavGroup group) {
  switch (group) {
    case _NavGroup.main:
      return 0;
    case _NavGroup.sales:
      return 1;
    case _NavGroup.purchasing:
      return 2;
    case _NavGroup.inventory:
      return 3;
    case _NavGroup.treasury:
      return 4;
    case _NavGroup.accounting:
      return 5;
    case _NavGroup.reports:
      return 6;
  }
}

String _groupLabel(_NavGroup group, AppStrings s) {
  switch (group) {
    case _NavGroup.main:
      return s.dashboard;
    case _NavGroup.sales:
      return s.sales;
    case _NavGroup.purchasing:
      return s.purchasing;
    case _NavGroup.inventory:
      return s.inventory;
    case _NavGroup.treasury:
      return s.treasury;
    case _NavGroup.accounting:
      return s.accounting;
    case _NavGroup.reports:
      return s.reports;
  }
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
  _Destination(
    label: (s) => s.openingBalances,
    icon: Icons.account_balance_wallet_outlined,
    permission: 'openingBalances',
    builder: _openingBalances,
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
Widget _openingBalances() => const OpeningBalancesScreen();
// Widget _settings() => const SettingsScreen(); // الإعدادات في شريط الأعلى الآن

/// Responsive application shell: a [NavigationRail] on wide layouts and a
/// [NavigationDrawer] on narrow ones. The AppBar shows the signed-in user,
/// their role and a logout action.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

/// Width of the collapsed navigation rail (icon-only, labels below icons).
const double _railCollapsedWidth = 76;

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _bootstrapped = false;
  final ScrollController _railScrollController = ScrollController();
  final ScrollController _drawerScrollController = ScrollController();

  @override
  void dispose() {
    _railScrollController.dispose();
    _drawerScrollController.dispose();
    super.dispose();
  }

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
        .toList()
      ..sort(
        (a, b) => _groupRank(_groupFor(a)).compareTo(_groupRank(_groupFor(b))),
      );

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

    final drawerTiles = <Widget>[_DrawerHeader(session: session)];
    _NavGroup? lastGroup;
    for (var i = 0; i < destinations.length; i++) {
      final group = _groupFor(destinations[i]);
      if (group != lastGroup) {
        lastGroup = group;
        drawerTiles.add(_DrawerGroupLabel(label: _groupLabel(group, s)));
      }
      drawerTiles.add(
        _DrawerTile(
          icon: destinations[i].icon,
          label: destinations[i].label(s),
          selected: i == index,
          onTap: () {
            Navigator.of(context).pop();
            setState(() => _index = i);
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(destination.label(s)),
        surfaceTintColor: Colors.transparent,
        actions: <Widget>[
          if (session.can('settings')) const _SettingsButton(),
          const _LanguageButton(),
          _UserMenu(session: session),
          const SizedBox(width: 12),
        ],
      ),
      drawer: isWide
          ? null
          : Drawer(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Scrollbar(
                    controller: _drawerScrollController,
                    thumbVisibility: true,
                    child: ListView(
                      controller: _drawerScrollController,
                      padding: EdgeInsets.zero,
                      children: <Widget>[
                        ...drawerTiles,
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      body: Row(
        children: <Widget>[
          if (isWide)
            // Wrap the rail so its destinations scroll when they exceed the
            // available height (long menus on short screens).
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
              child: SizedBox(
                width: isExtraWide ? 236 : _railCollapsedWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withAlpha(179),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(5),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Scrollbar(
                        controller: _railScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _railScrollController,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                              minWidth: constraints.maxWidth,
                            ),
                            child: IntrinsicHeight(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: NavigationRail(
                                  backgroundColor: Colors.transparent,
                                  selectedIndex: index,
                                  extended: isExtraWide,
                                  labelType: isExtraWide
                                      ? null
                                      : NavigationRailLabelType.all,
                                  onDestinationSelected: (value) =>
                                      setState(() => _index = value),
                                  destinations: <NavigationRailDestination>[
                                    for (final item in destinations)
                                      NavigationRailDestination(
                                        icon: Icon(item.icon),
                                        selectedIcon: Icon(item.icon),
                                        label: Text(item.label(s)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ClipRect(
              child: destination.builder(),
            ),
          ),
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

class _DrawerGroupLabel extends StatelessWidget {
  const _DrawerGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 6),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// A single drawer navigation row matching the Material look of the shell.
class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
