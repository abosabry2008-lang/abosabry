import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../models/app_settings.dart';
import '../../models/currency.dart';
import '../../state/currencies_controller.dart';
import '../../state/settings_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

/// Company settings plus a currencies tab.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<SettingsController>();
      if (controller.settings == null && !controller.loading) {
        controller.load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          TabBar(
            tabs: <Widget>[
              Tab(text: s.company),
              Tab(text: s.currencies),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _CompanySettingsTab(),
                CurrenciesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanySettingsTab extends StatefulWidget {
  const _CompanySettingsTab();

  @override
  State<_CompanySettingsTab> createState() => _CompanySettingsTabState();
}

class _CompanySettingsTabState extends State<_CompanySettingsTab> {
  final _formKey = GlobalKey<FormState>();
  AppSettings? _draft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final controller = context.read<SettingsController>();
    if (controller.settings == null) {
      await controller.load();
    }
    if (!mounted) return;
    setState(() => _draft = controller.settings ?? const AppSettings());
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final draft = _draft;
    if (draft == null) return;
    final controller = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await controller.save(draft);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? context.s.settingsSaved : (controller.error ?? context.s.couldNotSave),
        ),
      ),
    );
  }

  void _toggleDashboardWidget(String key, bool enabled) {
    final draft = _draft;
    if (draft == null) return;
    final next = AppSettings.parseDashboardWidgets(draft.dashboardWidgets);
    if (enabled) {
      next.add(key);
    } else {
      next.remove(key);
    }
    setState(
      () => _draft = draft.copyWith(
        dashboardWidgets: AppSettings.encodeDashboardWidgets(next),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<SettingsController>();
    final draft = _draft;
    final enabledWidgets =
        AppSettings.parseDashboardWidgets(draft?.dashboardWidgets);

    if (draft == null && controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (draft == null) {
      return ErrorView(
        message: controller.error ?? s.couldNotLoadSettings,
        onRetry: _load,
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: s.company,
            child: Column(
              children: <Widget>[
                AppTextField(
                  label: s.companyName,
                  initialValue: draft.companyName,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? s.companyNameRequired
                      : null,
                  onChanged: (value) =>
                      setState(() => _draft = draft.copyWith(companyName: value)),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: s.email,
                  initialValue: draft.companyEmail,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (value) =>
                      setState(() => _draft = draft.copyWith(companyEmail: value)),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: s.phone,
                  initialValue: draft.companyPhone,
                  keyboardType: TextInputType.phone,
                  onChanged: (value) =>
                      setState(() => _draft = draft.copyWith(companyPhone: value)),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: s.address,
                  initialValue: draft.companyAddress,
                  maxLines: 2,
                  onChanged: (value) => setState(
                    () => _draft = draft.copyWith(companyAddress: value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: s.defaults,
            child: Column(
              children: <Widget>[
                AppTextField(
                  label: s.baseCurrencyCode,
                  initialValue: draft.baseCurrencyCode,
                  helperText: s.baseCurrencyHelper,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? s.baseCurrencyRequired
                      : null,
                  onChanged: (value) => setState(
                    () => _draft = draft.copyWith(
                      baseCurrencyCode: value.trim().toUpperCase(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppNumberField(
                  label: s.defaultTaxRate,
                  initialValue: Formatters.number(draft.defaultTaxRate),
                  validator: (value) {
                    final rate = double.tryParse((value ?? '').trim());
                    if (rate == null || rate < 0 || rate > 100) {
                      return s.enterRate;
                    }
                    return null;
                  },
                  onChanged: (value) => setState(
                    () => _draft = draft.copyWith(defaultTaxRate: value),
                  ),
                ),
                const SizedBox(height: 12),
                AppSwitchField(
                  label: s.lowStockAlertsSetting,
                  value: draft.lowStockAlerts,
                  onChanged: (value) => setState(
                    () => _draft = draft.copyWith(lowStockAlerts: value),
                  ),
                ),
                const SizedBox(height: 12),
                AppSwitchField(
                  label: s.enableTax,
                  value: draft.taxEnabled,
                  onChanged: (value) => setState(
                    () => _draft = draft.copyWith(taxEnabled: value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                  child: Text(
                    s.enableTaxHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: s.dashboardLayout,
            subtitle: s.dashboardLayoutHint,
            child: Column(
              children: <Widget>[
                AppSwitchField(
                  label: s.dashKpis,
                  value: enabledWidgets.contains('kpis'),
                  onChanged: (value) => _toggleDashboardWidget('kpis', value),
                ),
                AppSwitchField(
                  label: s.dashQuickActions,
                  value: enabledWidgets.contains('quickActions'),
                  onChanged: (value) =>
                      _toggleDashboardWidget('quickActions', value),
                ),
                AppSwitchField(
                  label: s.dashLowStock,
                  value: enabledWidgets.contains('lowStock'),
                  onChanged: (value) =>
                      _toggleDashboardWidget('lowStock', value),
                ),
                AppSwitchField(
                  label: s.dashRecentMovements,
                  value: enabledWidgets.contains('recentMovements'),
                  onChanged: (value) =>
                      _toggleDashboardWidget('recentMovements', value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: s.numberPrefixes,
            child: Column(
              children: <Widget>[
                _PrefixField(
                  label: s.invoice,
                  value: draft.invoicePrefix,
                  onChanged: (value) =>
                      setState(() => _draft = draft.copyWith(invoicePrefix: value)),
                ),
                const SizedBox(height: 12),
                _PrefixField(
                  label: s.salesOrder,
                  value: draft.salesOrderPrefix,
                  onChanged: (value) => setState(
                    () => _draft = draft.copyWith(salesOrderPrefix: value),
                  ),
                ),
                const SizedBox(height: 12),
                _PrefixField(
                  label: s.purchaseOrder,
                  value: draft.purchaseOrderPrefix,
                  onChanged: (value) => setState(
                    () => _draft = draft.copyWith(purchaseOrderPrefix: value),
                  ),
                ),
                const SizedBox(height: 12),
                _PrefixField(
                  label: s.payment,
                  value: draft.paymentPrefix,
                  onChanged: (value) =>
                      setState(() => _draft = draft.copyWith(paymentPrefix: value)),
                ),
                const SizedBox(height: 12),
                _PrefixField(
                  label: s.journalEntry,
                  value: draft.journalPrefix,
                  onChanged: (value) =>
                      setState(() => _draft = draft.copyWith(journalPrefix: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: controller.saving ? null : _save,
            icon: controller.saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(controller.saving ? s.saving : s.saveSettings),
          ),
        ],
      ),
    );
  }
}

class _PrefixField extends StatelessWidget {
  const _PrefixField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      initialValue: value,
      validator: (input) =>
          (input ?? '').trim().isEmpty ? context.s.prefixRequired : null,
      onChanged: onChanged,
    );
  }
}

/// Read-only currency list (currencies cannot be managed from the mobile app).
class CurrenciesTab extends StatefulWidget {
  const CurrenciesTab({super.key});

  @override
  State<CurrenciesTab> createState() => _CurrenciesTabState();
}

class _CurrenciesTabState extends State<CurrenciesTab> {
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<CurrenciesController>();
    return AsyncListView<Currency>(
      controller: controller,
      emptyIcon: Icons.attach_money_outlined,
      emptyTitle: s.noCurrencies,
      emptyMessage: s.currenciesManagedHint,
      itemBuilder: (context, currency, index) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        child: ListTile(
          leading: CircleAvatar(child: Text(currency.symbol)),
          title: Text('${currency.code} · ${currency.name}'),
          subtitle: Text(
            s.rateValue(
              Formatters.number(currency.exchangeRate, decimals: 4),
            ),
          ),
          trailing: currency.isBase
              ? StatusChip(status: 'ACTIVE', label: s.baseLabel, compact: true)
              : null,
        ),
      ),
    );
  }
}
