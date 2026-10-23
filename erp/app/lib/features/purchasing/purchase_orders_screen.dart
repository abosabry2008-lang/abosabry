import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../models/purchase_order.dart';
import '../../state/purchase_orders_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/page_header.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../shell/navigation.dart';
import 'purchase_order_detail_screen.dart';
import 'purchase_order_form_screen.dart';

const List<String> purchaseOrderStatuses = <String>[
  'DRAFT',
  'PENDING',
  'APPROVED',
  'PARTIALLY_RECEIVED',
  'RECEIVED',
  'CANCELLED',
];

/// Purchase order list with status filter and search.
class PurchaseOrdersScreen extends StatelessWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<PurchaseOrdersController>();
    return Scaffold(
      body: Column(
        children: <Widget>[
          PageHeader(
            title: s.purchasing,
            filters: <Widget>[
              AppSearchField(
                hintText: s.searchPurchaseOrdersHint,
                initialValue: controller.search,
                onChanged: controller.searchWith,
              ),
              AppSelectField<String>(
                label: s.statusWord,
                value: controller.status,
                hint: s.allStatuses,
                options: <SelectOption<String>>[
                  SelectOption<String>('', s.allStatuses),
                  ...purchaseOrderStatuses.map(
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
          const SizedBox(height: 8),
          Expanded(
            child: AsyncListView<PurchaseOrder>(
              controller: controller,
              emptyIcon: Icons.shopping_cart_outlined,
              emptyTitle: s.noPurchaseOrders,
              emptyMessage: s.createPurchaseOrderHint,
              itemBuilder: (context, order, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: const Icon(Icons.shopping_cart_outlined),
                  title: Text(order.number),
                  subtitle: Text(
                    '${order.supplierName ?? s.supplier} · '
                    '${Formatters.date(order.orderDate)}',
                  ),
                  onTap: () => pushScreen<void>(
                    context,
                    order.number,
                    PurchaseOrderDetailScreen(orderId: order.id),
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
          s.newPurchaseOrder,
          const PurchaseOrderFormScreen(),
        ),
        icon: const Icon(Icons.add),
        label: Text(s.purchaseOrder),
      ),
    );
  }
}
