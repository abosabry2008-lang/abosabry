import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/opening_balance.dart';
import '../../state/opening_balances_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import 'opening_balance_form_screen.dart';

/// Log of opening-balance entries (مديونية سابقة) with an admin create/cancel
/// action. Posting the entry raises the capital journal and sets balances.
class OpeningBalancesScreen extends StatefulWidget {
  const OpeningBalancesScreen({super.key});

  @override
  State<OpeningBalancesScreen> createState() => _OpeningBalancesScreenState();
}

class _OpeningBalancesScreenState extends State<OpeningBalancesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OpeningBalancesController>().ensureLoaded();
    });
  }

  Future<void> _openForm() async {
    final controller = context.read<OpeningBalancesController>();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const OpeningBalanceFormScreen(),
      ),
    );
    if (saved == true) {
      await controller.refresh();
    }
  }

  Future<void> _cancel(OpeningBalance entry) async {
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.cancelOpeningBalanceQ,
      message: s.cancelOpeningBalanceHint,
      confirmLabel: s.cancel,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final controller = context.read<OpeningBalancesController>();
    try {
      await controller.api.post('/opening-balances/${entry.id}/cancel');
      await controller.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.openingCancelled)),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<OpeningBalancesController>();
    final canWrite = context.watch<Session>().can('openingBalances');

    return Scaffold(
      body: Column(
        children: <Widget>[
          if (canWrite)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openForm,
                  icon: const Icon(Icons.post_add_outlined),
                  label: Text(s.newOpeningBalance),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody(context, controller)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    OpeningBalancesController controller,
  ) {
    final s = context.s;
    if (controller.loading && controller.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && controller.items.isEmpty) {
      return ErrorView(
        message: controller.error!,
        onRetry: controller.refresh,
      );
    }
    if (controller.items.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: s.noOpeningBalances,
        message: s.openingBalancesHint,
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
        itemCount: controller.items.length,
        itemBuilder: (context, index) {
          final entry = controller.items[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: ListTile(
                leading: Icon(
                  entry.isCancelled
                      ? Icons.cancel_outlined
                      : Icons.account_balance_wallet_outlined,
                  color: entry.isCancelled
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Row(
                  children: <Widget>[
                    Expanded(child: Text(entry.number)),
                    if (entry.isCancelled)
                      Text(
                        s.cancelled,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                  ],
                ),
                subtitle: Text(
                  '${Formatters.date(entry.asOfDate)}'
                  '${entry.note == null || entry.note!.isEmpty ? '' : ' · ${entry.note}'}',
                ),
                trailing: MoneyText(
                  entry.capital,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                onTap: () => _showDetails(context, entry),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDetails(BuildContext context, OpeningBalance entry) {
    final s = context.s;
    final canWrite = context.read<Session>().can('openingBalances');
    final isAdmin = context.read<Session>().isAdmin;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(entry.number, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _DetailRow(label: s.asOfDate, value: Formatters.date(entry.asOfDate)),
            _DetailRow(
              label: s.openingCustomers,
              value: Formatters.money(entry.customerTotal),
            ),
            _DetailRow(
              label: s.openingInventory,
              value: Formatters.money(entry.inventoryTotal),
            ),
            _DetailRow(
              label: s.openingSuppliers,
              value: Formatters.money(entry.supplierTotal),
            ),
            const Divider(),
            _DetailRow(
              label: s.openingCapital,
              value: Formatters.money(entry.capital),
              emphasise: true,
            ),
            if (entry.note != null && entry.note!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              _DetailRow(label: s.note, value: entry.note!),
            ],
            if (entry.userName != null)
              _DetailRow(label: s.user, value: entry.userName!),
            const SizedBox(height: 16),
            if (!entry.isCancelled && canWrite && isAdmin)
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _cancel(entry);
                },
                icon: const Icon(Icons.cancel_outlined),
                label: Text(s.cancelOpeningBalanceQ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasise ? theme.textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
