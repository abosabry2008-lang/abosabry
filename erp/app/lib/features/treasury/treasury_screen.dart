import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/cash_box.dart';
import '../../models/collection_voucher.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/money_text.dart';
import '../payments/payments_screen.dart';
import '../shell/navigation.dart';
import 'box_detail_screen.dart';
import 'box_form_screen.dart';
import 'collection_detail_screen.dart';
import 'collection_form_screen.dart';
import 'transfer_form_screen.dart';
import '../expenses/expenses_screen.dart';

/// Treasury (الخزينة): cash boxes, agent collection receipts and payments.
class TreasuryScreen extends StatefulWidget {
  const TreasuryScreen({super.key});

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  List<CashBox> _boxes = <CashBox>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boxes = await api.getList('/treasury/boxes');
      if (!mounted) return;
      setState(() {
        _boxes = boxes.map(CashBox.fromJson).toList()
          ..sort((a, b) {
            if (a.isMain != b.isMain) return a.isMain ? -1 : 1;
            return a.name.compareTo(b.name);
          });
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _totalBalance =>
      _boxes.fold<double>(0, (sum, box) => sum + box.balance);

  Future<void> _openBox(CashBox box) async {
    await pushScreen<bool>(
      context,
      box.name,
      BoxDetailScreen(boxId: box.id, initialBox: box),
    );
    if (mounted) await _load();
  }

  Future<void> _newBox() async {
    final saved = await pushScreen<bool>(
      context,
      context.s.newCashBox,
      const BoxFormScreen(),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.boxSaved)),
        );
      }
    }
  }

  Future<void> _newTransfer({CashBox? from}) async {
    final saved = await pushScreen<bool>(
      context,
      context.s.newTransfer,
      TransferFormScreen(initialFromBoxId: from?.id, boxes: _boxes),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.transferSaved)),
        );
      }
    }
  }

  Future<void> _deleteBox(CashBox box) async {
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.deleteBoxQ,
      message: s.deleteBoxMessage,
      destructive: true,
      confirmLabel: s.delete,
    );
    if (!confirmed || !mounted) return;
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.delete('/treasury/boxes/${box.id}');
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(s.boxDeleted)));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = context.watch<Session>();
    final canManage = session.can('treasury.manage');
    return Column(
      children: <Widget>[
        _SummaryCard(
          total: _totalBalance,
          count: _boxes.length,
          loading: _loading,
          onRefresh: _load,
        ),
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabs,
            tabs: <Widget>[
              Tab(text: s.cashBoxes, icon: const Icon(Icons.account_balance_wallet_outlined)),
              Tab(text: s.collections, icon: const Icon(Icons.receipt_long_outlined)),
              Tab(text: s.payments, icon: const Icon(Icons.payments_outlined)),
              Tab(text: s.expensesTitle, icon: const Icon(Icons.call_made)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: <Widget>[
              _boxesTab(s, canManage),
              const _CollectionsTab(),
              const PaymentsScreen(),
              const ExpensesScreen(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _boxesTab(AppStrings s, bool canManage) {
    if (_loading && _boxes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _boxes.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_boxes.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: s.noCashBoxes,
        message: s.cashBoxesHint,
        action: canManage
            ? FilledButton.icon(
                onPressed: _newBox,
                icon: const Icon(Icons.add),
                label: Text(s.newCashBox),
              )
            : null,
      );
    }

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
            itemCount: _boxes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final box = _boxes[index];
              return _CashBoxCard(
                box: box,
                canManage: canManage,
                onTap: () => _openBox(box),
                onEdit: () async {
                  final saved = await pushScreen<bool>(
                    context,
                    context.s.editCashBox,
                    BoxFormScreen(box: box),
                  );
                  if (saved == true) await _load();
                },
                onDelete: () => _deleteBox(box),
              );
            },
          ),
        ),
        if (canManage)
          PositionedDirectional(
            end: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                FloatingActionButton.small(
                  heroTag: 'transfer_fab',
                  tooltip: s.newTransfer,
                  onPressed: () => _newTransfer(),
                  child: const Icon(Icons.swap_horiz),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'box_fab',
                  tooltip: s.newCashBox,
                  onPressed: _newBox,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.count,
    required this.loading,
    required this.onRefresh,
  });

  final double total;
  final int count;
  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.92),
            scheme.primary.withValues(alpha: 0.65),
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.totalInBoxes,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 4),
                MoneyText(
                  total,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.cashBoxes}: $count',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.refresh,
            onPressed: loading ? null : onRefresh,
            icon: loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : Icon(Icons.refresh, color: scheme.onPrimary),
          ),
        ],
      ),
    );
  }
}

class _CashBoxCard extends StatelessWidget {
  const _CashBoxCard({
    required this.box,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final CashBox box;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 22,
                backgroundColor: box.isMain
                    ? scheme.primaryContainer
                    : scheme.secondaryContainer,
                child: Icon(
                  box.isMain ? Icons.account_balance : Icons.savings_outlined,
                  color: box.isMain
                      ? scheme.onPrimaryContainer
                      : scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            box.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (box.isDefault) ...<Widget>[
                          const SizedBox(width: 6),
                          _Tag(label: s.defaultBox, color: scheme.primary),
                        ],
                        if (!box.active) ...<Widget>[
                          const SizedBox(width: 6),
                          _Tag(label: s.inactive, color: scheme.error),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${box.code} · ${box.isMain ? s.mainBox : s.subBox}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  MoneyText(
                    box.balance,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: box.balance < 0 ? scheme.error : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.currentBalance,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ],
              ),
              if (canManage)
                PopupMenuButton<String>(
                  tooltip: s.edit,
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: Text(s.edit),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, color: scheme.error),
                        title: Text(s.delete),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CollectionsTab extends StatefulWidget {
  const _CollectionsTab();

  @override
  State<_CollectionsTab> createState() => _CollectionsTabState();
}

class _CollectionsTabState extends State<_CollectionsTab>
    with AutomaticKeepAliveClientMixin {
  List<CollectionVoucher> _vouchers = <CollectionVoucher>[];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await api.getPage<CollectionVoucher>(
        '/treasury/collections',
        query: <String, dynamic>{
          'page': 1,
          'pageSize': 100,
          // Show cancelled receipts too — the row styles them with a tag and
          // a strikethrough, and admins need the full history.
          'includeCancelled': 'true',
        },
        parse: CollectionVoucher.fromJson,
      );
      if (!mounted) return;
      setState(() => _vouchers = page.items);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final saved = await pushScreen<bool>(
      context,
      context.s.newCollection,
      const CollectionFormScreen(),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.collectionSaved)),
        );
      }
    }
  }

  Future<void> _open(CollectionVoucher voucher) async {
    await pushScreen<bool>(
      context,
      voucher.number,
      CollectionDetailScreen(voucherId: voucher.id, initial: voucher),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = context.s;
    final session = context.watch<Session>();
    final canCreate = session.can('payments');
    final theme = Theme.of(context);

    if (_loading && _vouchers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _vouchers.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_vouchers.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: s.noCollections,
        message: s.collectionsHint,
        action: canCreate
            ? FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: Text(s.newCollection),
              )
            : null,
      );
    }

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: _vouchers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final voucher = _vouchers[index];
              return Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    child: Icon(
                      Icons.receipt_long_outlined,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  title: Row(
                    children: <Widget>[
                      Flexible(child: Text(voucher.number)),
                      if (voucher.cancelled) ...<Widget>[
                        const SizedBox(width: 6),
                        _Tag(
                          label: s.status('VOID'),
                          color: theme.colorScheme.error,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      <String>[
                        Formatters.date(voucher.collectedAt),
                        if (voucher.salespersonName.isNotEmpty)
                          voucher.salespersonName,
                        if (voucher.cashBoxName.isNotEmpty)
                          voucher.cashBoxName,
                        '${voucher.lines.length} ${s.collectionLines}',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  trailing: MoneyText(
                    voucher.total,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: voucher.cancelled
                          ? theme.colorScheme.outline
                          : null,
                      decoration:
                          voucher.cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  onTap: () => _open(voucher),
                ),
              );
            },
          ),
        ),
        if (canCreate)
          PositionedDirectional(
            end: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'collection_fab',
              tooltip: s.newCollection,
              onPressed: _create,
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}
