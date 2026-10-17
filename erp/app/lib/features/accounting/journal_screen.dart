import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../models/journal_entry.dart';
import '../../state/accounting_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';

/// Journal entry list with search and a detail sheet.
class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<JournalController>();
    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AppSearchField(
              hintText: s.searchJournalHint,
              initialValue: controller.search,
              onChanged: controller.searchWith,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncListView<JournalEntry>(
              controller: controller,
              emptyIcon: Icons.menu_book_outlined,
              emptyTitle: s.noJournalEntries,
              emptyMessage: s.journalHint,
              itemBuilder: (context, entry, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(entry.number),
                  subtitle: Text(
                    '${Formatters.date(entry.entryDate)}'
                    '${entry.memo == null ? '' : ' · ${entry.memo}'}',
                  ),
                  trailing: MoneyText(
                    entry.debitTotal,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  onTap: () => _showEntry(context, entry),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEntry(BuildContext context, JournalEntry entry) {
    final s = context.s;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            Text(entry.number, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${Formatters.date(entry.entryDate)}'
              '${entry.reference == null ? '' : ' · ${entry.reference}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (entry.memo != null && entry.memo!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(entry.memo!),
            ],
            const SizedBox(height: 16),
            if (entry.lines.isEmpty)
              Text(
                s.noLinesOnEntry,
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Column(
                children: <Widget>[
                  for (final line in entry.lines)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${line.accountCode ?? ''} ${line.accountName ?? ''}'
                            .trim(),
                      ),
                      subtitle: line.description == null ||
                              line.description!.isEmpty
                          ? null
                          : Text(line.description!),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          if (line.debit != 0)
                            MoneyText(
                              line.debit,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          if (line.credit != 0)
                            Text(
                              s.creditAmount(Formatters.money(line.credit)),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Row(
                    children: <Widget>[
                      Expanded(child: Text(s.totals)),
                      Text(
                        '${s.dr} ${Formatters.money(entry.debitTotal)} · '
                        '${s.cr} ${Formatters.money(entry.creditTotal)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
