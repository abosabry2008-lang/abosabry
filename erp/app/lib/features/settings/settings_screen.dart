import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/print_service.dart';
import '../../core/session.dart';
import '../../models/app_settings.dart';
import '../../models/currency.dart';
import '../../state/currencies_controller.dart';
import '../../state/settings_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import 'role_permissions_screen.dart';
import 'users_screen.dart';

/// Company settings, currencies and (for admins) users.
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
    final session = context.watch<Session>();
    final canUsers = session.can('users');
    // settings.write is admin-only, so this doubles as the admin check.
    final canBackup = session.can('settings.write');
    final canRolePerms =
        session.role == 'ADMIN' || session.can('roles.manage');
    final tabs = <Tab>[
      Tab(text: s.company),
      Tab(text: s.currencies),
      if (canRolePerms) const Tab(text: 'صلاحيات الأدوار'),
      if (canUsers) Tab(text: s.users),
      if (canBackup) Tab(text: s.backup),
    ];
    final views = <Widget>[
      _CompanySettingsTab(),
      CurrenciesTab(),
      if (canRolePerms) const RolePermissionsTab(),
      if (canUsers) UsersTab(),
      if (canBackup) const _BackupTab(),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: <Widget>[
          TabBar(tabs: tabs),
          Expanded(child: TabBarView(children: views)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backup (النسخة الاحتياطية) — admin only
// ---------------------------------------------------------------------------

class _BackupTab extends StatefulWidget {
  const _BackupTab();

  @override
  State<_BackupTab> createState() => _BackupTabState();
}

class _BackupTabState extends State<_BackupTab> {
  bool _busy = false;

  Future<void> _download() async {
    final s = context.s;
    setState(() => _busy = true);
    final ok = await PrintService.downloadBackup(context);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.backupFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SectionCard(
          title: s.backupTitle,
          subtitle: s.backup,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(s.backupHint),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _download,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_outlined),
                label: Text(_busy ? s.backupDownloading : s.downloadBackup),
              ),
            ],
          ),
        ),
      ],
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppTextField(
                        label: s.commercialRegister,
                        initialValue: draft.commercialRegisterNo,
                        onChanged: (value) => setState(
                          () => _draft =
                              draft.copyWith(commercialRegisterNo: value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        label: s.taxCard,
                        initialValue: draft.taxCardNo,
                        onChanged: (value) => setState(
                          () => _draft = draft.copyWith(taxCardNo: value),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: s.logoUrl,
                  initialValue: draft.logoUrl,
                  hint: s.logoUrlHint,
                  keyboardType: TextInputType.url,
                  onChanged: (value) => setState(
                    () => _draft = draft.copyWith(logoUrl: value),
                  ),
                ),
                if ((draft.logoUrl ?? '').trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        draft.logoUrl!.trim(),
                        height: 72,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.broken_image_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                ],
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

/// Currency management: list, add, edit, delete and choose the base currency.
class CurrenciesTab extends StatefulWidget {
  const CurrenciesTab({super.key});

  @override
  State<CurrenciesTab> createState() => _CurrenciesTabState();
}

class _CurrenciesTabState extends State<CurrenciesTab> {
  Future<void> _openForm({Currency? currency}) async {
    final result = await showDialog<Currency>(
      context: context,
      builder: (_) => _CurrencyFormDialog(currency: currency),
    );
    if (result == null || !mounted) return;
    await context.read<CurrenciesController>().refresh();
    if (result.isBase) await _syncBaseCurrency(result.code);
  }

  /// Keeps the settings base-currency code (used for money formatting)
  /// aligned when the user picks a different base currency.
  Future<void> _syncBaseCurrency(String code) async {
    final controller = context.read<SettingsController>();
    var settings = controller.settings;
    if (settings == null) {
      await controller.load();
      settings = controller.settings;
    }
    if (settings == null || settings.baseCurrencyCode == code) return;
    final saved =
        await controller.save(settings.copyWith(baseCurrencyCode: code));
    if (!mounted || !saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.s.baseCurrencyUpdated)),
    );
  }

  Future<void> _delete(Currency currency) async {
    final confirmed = await confirmDialog(
      context,
      title: context.s.deleteCurrencyQ(currency.code),
      message: context.s.deleteCurrencyMessage,
      confirmLabel: context.s.delete,
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<Session>().api.delete('/currencies/${currency.id}');
      if (!mounted) return;
      await context.read<CurrenciesController>().refresh();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.s.currencyDeleted)),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<CurrenciesController>();
    final canWrite = context.watch<Session>().can('currency.write');
    return Scaffold(
      body: AsyncListView<Currency>(
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (currency.isBase)
                  StatusChip(status: 'ACTIVE', label: s.baseLabel, compact: true),
                if (canWrite)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: s.edit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _openForm(currency: currency),
                  ),
                if (canWrite && !currency.isBase)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: s.delete,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _delete(currency),
                  ),
              ],
            ),
            onTap: canWrite ? () => _openForm(currency: currency) : null,
          ),
        ),
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: Text(s.addCurrency),
            )
          : null,
    );
  }
}

class _CurrencyFormDialog extends StatefulWidget {
  const _CurrencyFormDialog({this.currency});

  final Currency? currency;

  @override
  State<_CurrencyFormDialog> createState() => _CurrencyFormDialogState();
}

class _CurrencyFormDialogState extends State<_CurrencyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code =
      TextEditingController(text: widget.currency?.code ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.currency?.name ?? '');
  late final TextEditingController _symbol =
      TextEditingController(text: widget.currency?.symbol ?? '');
  late final TextEditingController _rate = TextEditingController(
    text: widget.currency == null
        ? ''
        : Formatters.number(widget.currency!.exchangeRate, decimals: 4),
  );
  late bool _isBase = widget.currency?.isBase ?? false;
  late bool _active = widget.currency?.active ?? true;
  bool _saving = false;

  bool get _isEdit => widget.currency != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _symbol.dispose();
    _rate.dispose();
    super.dispose();
  }

  double? get _parsedRate =>
      double.tryParse(_rate.text.trim().replaceAll(',', ''));

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // The system must always keep exactly one base currency: allow switching
    // the base to another currency, but not simply unsetting it.
    if (_isEdit && widget.currency!.isBase && !_isBase) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.keepBaseCurrency)),
      );
      return;
    }
    setState(() => _saving = true);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final code = _code.text.trim().toUpperCase();
    final body = <String, dynamic>{
      'code': code,
      'name': _name.text.trim(),
      'symbol': _symbol.text.trim(),
      'exchangeRate': _parsedRate,
      'isBase': _isBase,
      'active': _active,
    };
    try {
      if (_isEdit) {
        await api.patch('/currencies/${widget.currency!.id}', body: body);
      } else {
        await api.post('/currencies', body: body);
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEdit ? context.s.currencyUpdated : context.s.currencyCreated,
          ),
        ),
      );
      navigator.pop(
        Currency(
          id: widget.currency?.id ?? '',
          code: code,
          name: _name.text.trim(),
          symbol: _symbol.text.trim(),
          exchangeRate: _parsedRate ?? 1,
          isBase: _isBase,
          active: _active,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AlertDialog(
      title: Text(_isEdit ? s.editCurrency : s.addCurrency),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppTextField(
                label: s.code,
                controller: _code,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? s.currencyCodeRequired
                    : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: s.name,
                controller: _name,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? s.nameRequired : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: s.symbol,
                controller: _symbol,
              ),
              const SizedBox(height: 12),
              AppNumberField(
                label: s.exchangeRateLabel,
                controller: _rate,
                enabled: !_isBase,
                helperText: _isBase ? s.baseCurrencyHelper : null,
                validator: (value) {
                  if (_isBase) return null;
                  final rate = double.tryParse(
                    (value ?? '').trim().replaceAll(',', ''),
                  );
                  if (rate == null || rate <= 0) return s.enterPositiveRate;
                  return null;
                },
              ),
              const SizedBox(height: 8),
              AppSwitchField(
                label: s.setAsBaseLabel,
                value: _isBase,
                onChanged: (value) => setState(() => _isBase = value),
              ),
              AppSwitchField(
                label: s.active,
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? s.saving : s.save),
        ),
      ],
    );
  }
}
