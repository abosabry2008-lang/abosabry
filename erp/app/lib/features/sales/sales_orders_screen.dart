import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../models/sales_order.dart';
import '../../state/sales_orders_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../shell/navigation.dart';
import 'sales_order_detail_screen.dart';
import 'sales_order_form_screen.dart';

const List<String> salesOrderStatuses = <String>[
  'DRAFT',
  'CONFIRMED',
  'PARTIALLY_FULFILLED',
  'FULFILLED',
  'CANCELLED',
];

/// Sales order list with status filter and search.
class SalesOrdersScreen extends StatelessWidget {
  const SalesOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<SalesOrdersController>();
    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: <Widget>[
                AppSearchField(
                  hintText: s.searchSalesOrdersHint,
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
                    ...salesOrderStatuses.map(
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
            child: AsyncListView<SalesOrder>(
              controller: controller,
              emptyIcon: Icons.receipt_long_outlined,
              emptyTitle: s.noSalesOrders,
              emptyMessage: s.createSalesOrderHint,
              itemBuilder: (context, order, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(order.number),
                  subtitle: Text(
                    '${order.customerName ?? s.walkInCustomer} · '
                    '${Formatters.date(order.orderDate)}',
                  ),
                  onTap: () => pushScreen<void>(
                    context,
                    order.number,
                    SalesOrderDetailScreen(orderId: order.id, initial: order),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      MoneyText(
                        order.total,
                        currencyCode: order.currencyCode,
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
          s.newSalesOrder,
          const SalesOrderFormScreen(),
        ),
        icon: const Icon(Icons.add),
        label: Text(s.salesOrder),
      ),
    );
  }
}
