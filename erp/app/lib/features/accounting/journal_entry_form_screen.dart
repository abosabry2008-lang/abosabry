import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/account.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// One editable debit/credit line of a manual journal entry.
class _LineDraft {
  _LineDraft();

  final TextEditingController debit = TextEditingController();
  final TextEditingController credit = TextEditingController();
  final TextEditingController description = TextEditingController();
  String? accountId;

  double get debitValue => double.tryParse(debit.text.trim()) ?? 0;
  double get creditValue => double.tryParse(credit.text.trim()) ?? 0;

  bool get isEmpty =>
      accountId == null &&
      debitValue == 0 &&
      creditValue == 0 &&
      description.text.trim().isEmpty;

  void dispose() {
    debit.dispose();
    credit.dispose();
    description.dispose();
  }
}

/// A manually written double-entry journal entry (`POST /accounting/journal`).
class JournalEntryFormScreen extends StatefulWidget {
  const JournalEntryFormScreen({super.key});

  @override
  State<JournalEntryFormScreen> createState() => _JournalEntryFormScreenState();
}

class _JournalEntryFormScreenState extends State<JournalEntryFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _memo = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final List<_LineDraft> _lines = <_LineDraft>[_LineDraft(), _LineDraft()];
  List<Account> _accounts = <Account>[];
  DateTime _entryDate = DateTime.now();
  bool _saving = false;
  bool _loadingAccounts = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccounts());
  }

  @override
  void dispose() {
    _memo.dispose();
    _reference.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final page = await context.read<Session>().api.getPage<Account>(
            '/accounting/accounts',
            query: <String, dynamic>{'page': 1, 'pageSize': 200},
            parse: Account.fromJson,
          );
      if (!mounted) return;
      setState(() {
        _accounts = page.items;
        _loadingAccounts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAccounts = false);
    }
  }

  double get _debitTotal =>
      _lines.fold<double>(0, (sum, line) => sum + line.debitValue);
  double get _creditTotal =>
      _lines.fold<double>(0, (sum, line) => sum + line.creditValue);
  bool get _balanced => _debitTotal > 0 && (_debitTotal - _creditTotal).abs() < 0.01;

  void _addLine() => setState(() => _lines.add(_LineDraft()));

  void _removeLine(_LineDraft line) {
    setState(() {
      line.dispose();
      _lines.remove(line);
      if (_lines.isEmpty) _lines.add(_LineDraft());
    });
  }

  /// Client-side checks mirroring the API rules; returns `null` when OK.
  String? _validate() {
    final s = context.s;
    final filled = _lines.where((line) => !line.isEmpty).toList();
    for (final line in filled) {
      if (line.accountId == null) return s.lineNeedsAccount;
      final hasDebit = line.debitValue > 0;
      final hasCredit = line.creditValue > 0;
      if (hasDebit == hasCredit) return s.lineNeedsAmountSide;
    }
    if (filled.length < 2) return s.lineNeedsAccount;
    if (_debitTotal <= 0) return s.lineNeedsAmountSide;
    if (filled.any((line) => line.accountId == null)) return s.lineNeedsAccount;
    return _balanced ? null : s.notBalanced;
  }

  Future<void> _submit() async {
    final s = context.s;
    final problem = _validate();
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final lines = _lines
        .where((line) => !line.isEmpty)
        .map(
          (line) => <String, dynamic>{
            'accountId': line.accountId,
            'debit': line.debitValue,
            'credit': line.creditValue,
            'description': line.description.text.trim().isEmpty
                ? null
                : line.description.text.trim(),
          },
        )
        .toList();
    try {
      await api.postObject(
        '/accounting/journal',
        body: <String, dynamic>{
          'entryDate': _entryDate.toUtc().toIso8601String(),
          'memo': _memo.text.trim().isEmpty ? null : _memo.text.trim(),
          'reference':
              _reference.text.trim().isEmpty ? null : _reference.text.trim(),
          'lines': lines,
        },
      );
      messenger.showSnackBar(SnackBar(content: Text(s.journalSaved)));
      navigator.pop(true);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: s.newJournalEntry,
            subtitle: s.manualEntry,
            child: Column(
              children: <Widget>[
                AppDateField(
                  label: s.entryDate,
                  value: _entryDate,
                  enabled: !_saving,
                  onChanged: (value) =>
                      setState(() => _entryDate = value ?? _entryDate),
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: s.memo,
                  controller: _memo,
                  enabled: !_saving,
                  prefixIcon: Icons.notes_outlined,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: s.reference,
                  controller: _reference,
                  enabled: !_saving,
                  prefixIcon: Icons.tag_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: s.lines,
            trailing: _loadingAccounts
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            child: Column(
              children: <Widget>[
                for (var index = 0; index < _lines.length; index++)
                  _JournalLineEditor(
                    key: ObjectKey(_lines[index]),
                    index: index,
                    line: _lines[index],
                    enabled: !_saving,
                    accounts: _accounts,
                    onAccountChanged: (value) =>
                        setState(() => _lines[index].accountId = value),
                    onChanged: () => setState(() {}),
                    onRemove: _lines.length > 2
                        ? () => _removeLine(_lines[index])
                        : null,
                  ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _addLine,
                    icon: const Icon(Icons.add),
                    label: Text(s.addLine),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: s.totals,
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('${s.debit} · ${s.credit}'),
                    ),
                    Text(
                      '${Formatters.money(_debitTotal)} · '
                      '${Formatters.money(_creditTotal)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(
                      _balanced
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 18,
                      color: _balanced
                          ? Colors.green
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _balanced ? s.balanced : s.notBalanced,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.how_to_reg_outlined),
            label: Text(s.save),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _JournalLineEditor extends StatelessWidget {
  const _JournalLineEditor({
    super.key,
    required this.index,
    required this.line,
    required this.enabled,
    required this.accounts,
    required this.onAccountChanged,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _LineDraft line;
  final bool enabled;
  final List<Account> accounts;
  final ValueChanged<String?> onAccountChanged;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '#${index + 1}',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: s.delete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: enabled ? onRemove : null,
                ),
            ],
          ),
          AppSelectField<String?>(
            label: s.accountWord,
            value: line.accountId,
            enabled: enabled,
            hint: s.lineNeedsAccount,
            prefixIcon: Icons.account_tree_outlined,
            options: <SelectOption<String?>>[
              SelectOption<String?>(null, s.lineNeedsAccount),
              for (final account in accounts)
                SelectOption<String?>(
                  account.id,
                  '${account.code} · ${account.name} · ${s.status(account.type)}',
                ),
            ],
            onChanged: (value) {
              onAccountChanged(value);
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: AppNumberField(
                  label: s.debit,
                  controller: line.debit,
                  enabled: enabled,
                  prefixIcon: Icons.add_circle_outline,
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppNumberField(
                  label: s.credit,
                  controller: line.credit,
                  enabled: enabled,
                  prefixIcon: Icons.remove_circle_outline,
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppTextField(
            label: s.description,
            controller: line.description,
            enabled: enabled,
            prefixIcon: Icons.short_text_outlined,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}
