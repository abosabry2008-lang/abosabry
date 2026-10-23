import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../models/payment.dart';
import '../../state/payments_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/day_search_row.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../shell/navigation.dart';
import 'payment_form_screen.dart';

/// Payment list with direction filter and search.
class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<PaymentsController>();
    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: <Widget>[
                AppSearchField(
                  hintText: s.searchPaymentsHint,
                  initialValue: controller.search,
                  onChanged: controller.searchWith,
                ),
                const SizedBox(height: 8),
                DaySearchRow(
                  day: controller.dayFilter.day,
                  onDayChanged: controller.filterByDay,
                  onSearch: () => controller.refresh(),
                ),
                const SizedBox(height: 8),
                AppSelectField<String>(
                  label: s.direction,
                  value: controller.direction,
                  hint: s.allPayments,
                  options: <SelectOption<String>>[
                    SelectOption<String>('', s.allPayments),
                    SelectOption<String>('INBOUND', s.inboundReceived),
                    SelectOption<String>('OUTBOUND', s.outboundPaid),
                  ],
                  onChanged: (value) => controller.filterByDirection(
                    value == null || value.isEmpty ? null : value,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncListView<Payment>(
              controller: controller,
              emptyIcon: Icons.payments_outlined,
              emptyTitle: s.noPayments,
              emptyMessage: s.paymentsHint,
              itemBuilder: (context, payment, index) {
                final inbound = payment.isInbound;
                final counterparty = inbound
                    ? (payment.customerName ?? s.walkInCustomer)
                    : (payment.supplierName ?? s.supplier);
                return SectionCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: (inbound
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFB26A00))
                          .withValues(alpha: 0.12),
                      child: Icon(
                        inbound
                            ? Icons.call_received
                            : Icons.call_made,
                        color: inbound
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFB26A00),
                      ),
                    ),
                    title: Text(counterparty),
                    subtitle: Text(
                      '${payment.number} · ${s.status(payment.method)}'
                      '${payment.invoiceNumber == null ? '' : ' · ${payment.invoiceNumber}'}'
                      ' · ${Formatters.date(payment.paidAt)}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        MoneyText(
                          inbound ? payment.amount : -payment.amount,
                          currencyCode: payment.currencyCode,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        StatusChip(
                          status: inbound ? 'RECEIVED' : 'PAID',
                          label: inbound ? s.inbound : s.outbound,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => pushScreen<bool>(
          context,
          s.recordPayment,
          const PaymentFormScreen(),
        ),
        icon: const Icon(Icons.add),
        label: Text(s.payment),
      ),
    );
  }
}
