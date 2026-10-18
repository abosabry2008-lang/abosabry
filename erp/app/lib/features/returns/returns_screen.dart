import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../models/return_order.dart';
import '../../state/returns_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../shell/navigation.dart';
import 'return_order_detail_screen.dart';
import 'return_order_form_screen.dart';

const List<String> returnOrderStatuses = <String>[
  'DRAFT',
  'POSTED',
  'CANCELLED',
];

/// Return orders list (customer + supplier returns) with filters and search.
class ReturnsScreen extends StatelessWidget {
  const ReturnsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<ReturnsController>();
    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: <Widget>[
                AppSearchField(
                  hintText: s.searchReturnsHint,
                  initialValue: controller.search,
                  onChanged: controller.searchWith,
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppSelectField<String>(
                        label: s.returnType,
                        value: controller.type ?? '',
                        hint: s.allStatuses,
                        options: <SelectOption<String>>[
                          SelectOption<String>('', s.returns),
                          SelectOption<String>(
                            'CUSTOMER_RETURN',
                            s.customerReturns,
                          ),
                          SelectOption<String>(
                            'SUPPLIER_RETURN',
                            s.supplierReturns,
                          ),
                        ],
                        onChanged: (value) => controller.filterByType(
                          value == null || value.isEmpty ? null : value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppSelectField<String>(
                        label: s.statusWord,
                        value: controller.status ?? '',
                        hint: s.allStatuses,
                        options: <SelectOption<String>>[
                          SelectOption<String>('', s.allStatuses),
                          ...returnOrderStatuses.map(
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
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncListView<ReturnOrder>(
              controller: controller,
              emptyIcon: Icons.keyboard_return_outlined,
              emptyTitle: s.noReturnsYet,
              emptyMessage: s.noReturnsHint,
              itemBuilder: (context, order, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: Icon(
                    order.isCustomerReturn
                        ? Icons.person_outline
                        : Icons.local_shipping_outlined,
                  ),
                  title: Text(order.number),
                  subtitle: Text(
                    '${order.isCustomerReturn ? s.customerReturns : s.supplierReturns} · '
                    '${order.partnerName} · '
                    '${Formatters.date(order.returnDate)}',
                  ),
                  onTap: () => pushScreen<void>(
                    context,
                    order.number,
                    ReturnOrderDetailScreen(orderId: order.id, initial: order),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      MoneyText(
                        order.total,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      StatusChip(status: order.status, compact: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => pushScreen<void>(
          context,
          s.newReturn,
          const ReturnOrderFormScreen(),
        ),
        icon: const Icon(Icons.add),
        label: Text(s.returnOrder),
      ),
    );
  }
}
