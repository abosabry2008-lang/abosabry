import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../models/invoice.dart';
import '../../state/invoices_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../shell/navigation.dart';
import 'invoice_detail_screen.dart';

const List<String> invoiceStatuses = <String>[
  'DRAFT',
  'ISSUED',
  'PARTIALLY_PAID',
  'PAID',
  'VOID',
];

/// Invoice list with status filter and search.
class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<InvoicesController>();
    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: <Widget>[
                AppSearchField(
                  hintText: s.searchInvoicesHint,
                  initialValue: controller.search,
                  onChanged: controller.searchWith,
                ),
                const SizedBox(height: 8),
                AppSelectField<String>(
                  label: s.statusWord,
                  value: controller.status,
                  hint: s.allStatuses,
                  options: <SelectOption<String>>[
                    SelectOption<String>('', s.allStatuses),
                    ...invoiceStatuses.map(
                      (status) => SelectOption<String>(
                        status,
                        s.status(status),
                      ),
                    ),
                  ],
                  onChanged: (value) => controller.filterByStatus(
                    value == null || value.isEmpty ? null : value,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncListView<Invoice>(
              controller: controller,
              emptyIcon: Icons.receipt_long_outlined,
              emptyTitle: s.noInvoices,
              emptyMessage: s.invoicesCreatedHint,
              itemBuilder: (context, invoice, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: Icon(Formatters.statusIcon(invoice.status)),
                  title: Text(invoice.number),
                  subtitle: Text(
                    '${invoice.customerName ?? s.walkInCustomer} · '
                    '${Formatters.date(invoice.issueDate)}'
                    '${invoice.isOverdue ? ' · ${s.overdue}' : ''}',
                  ),
                  onTap: () => pushScreen<void>(
                    context,
                    invoice.number,
                    InvoiceDetailScreen(invoiceId: invoice.id, initial: invoice),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      MoneyText(
                        invoice.total,
                        currencyCode: invoice.currencyCode,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      StatusChip(
                        status: invoice.isOverdue ? 'OVERDUE' : invoice.status,
                        label: invoice.isOverdue
                            ? s.overdue
                            : s.status(invoice.status),
                        compact: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
