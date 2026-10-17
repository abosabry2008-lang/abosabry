import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../models/customer.dart';
import '../../state/customers_controller.dart';
import '../../state/salespeople_controller.dart';
import '../../widgets/async_list_view.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_card.dart';
import '../shell/navigation.dart';
import 'customer_form_screen.dart';
import 'customer_statement_screen.dart';

/// Customer list with search, create, edit and delete.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalespeopleController>().ensureLoaded();
    });
  }

  Future<void> _delete(BuildContext context, Customer customer) async {
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.deleteCustomerQ,
      message: s.customerWillBeRemoved(customer.name),
      confirmLabel: s.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final controller = context.read<CustomersController>();
    try {
      await controller.api.delete('/customers/${customer.id}');
      controller.removeWhere((item) => item.id == customer.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.customerDeleted(customer.name))),
      );
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final controller = context.watch<CustomersController>();
    final salespeople = context.watch<SalespeopleController>().salespeople;
    final canManage = context.watch<Session>().can('customers');

    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: <Widget>[
                AppSearchField(
                  hintText: s.searchCustomersHint,
                  initialValue: controller.search,
                  onChanged: controller.searchWith,
                ),
                const SizedBox(height: 10),
                AppSelectField<String?>(
                  label: s.salesperson,
                  value: controller.salespersonId,
                  prefixIcon: Icons.support_agent_outlined,
                  options: <SelectOption<String?>>[
                    SelectOption<String?>(null, s.allSalespeople),
                    for (final person in salespeople)
                      SelectOption<String?>(person.id, person.name),
                  ],
                  onChanged: controller.filterBySalesperson,
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncListView<Customer>(
              controller: controller,
              emptyIcon: Icons.people_outline,
              emptyTitle: s.noCustomers,
              emptyMessage: s.addCustomerHint,
              itemBuilder: (context, customer, index) => SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(customer.name),
                  subtitle: Text(
                    <String>[
                      if (customer.email != null) customer.email!,
                      if (customer.phone != null) customer.phone!,
                      if (customer.salespersonName != null)
                        '${s.salesperson}: ${customer.salespersonName}',
                    ].join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          MoneyText(customer.balance, colorNegative: true),
                          Text(
                            s.balance,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: s.accountStatement,
                        icon: const Icon(Icons.list_alt_outlined),
                        onPressed: () => openCustomerStatement(
                          context,
                          customerId: customer.id,
                          customerName: customer.name,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => pushScreen<void>(
                    context,
                    customer.name,
                    CustomerFormScreen(customer: customer),
                  ),
                  onLongPress:
                      canManage ? () => _delete(context, customer) : null,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => pushScreen<void>(
                context,
                s.newCustomer,
                const CustomerFormScreen(),
              ),
              icon: const Icon(Icons.add),
              label: Text(s.customer),
            )
          : null,
    );
  }
}