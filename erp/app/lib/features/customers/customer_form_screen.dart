import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../models/customer.dart';
import '../../state/customers_controller.dart';
import '../../state/salespeople_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// Create / edit form for a customer.
class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.customer});

  final Customer? customer;

  bool get isEditing => customer != null;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.customer?.name ?? '');
  late final TextEditingController _code =
      TextEditingController(text: widget.customer?.code ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.customer?.email ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.customer?.phone ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.customer?.address ?? '');
  late final TextEditingController _taxId =
      TextEditingController(text: widget.customer?.taxId ?? '');
  late final TextEditingController _creditLimit =
      TextEditingController(text: (widget.customer?.creditLimit ?? 0).toString());
  late final TextEditingController _openingBalance = TextEditingController(text: '0');

  late bool _active = widget.customer?.active ?? true;

  /// Assigned sales representative (مندوب).
  late String? _salespersonId = widget.customer?.salespersonId;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalespeopleController>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _taxId.dispose();
    _creditLimit.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  Map<String, dynamic> _body() => <String, dynamic>{
        'name': _name.text.trim(),
        if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'taxId': _taxId.text.trim().isEmpty ? null : _taxId.text.trim(),
        'creditLimit': double.tryParse(_creditLimit.text.trim()) ?? 0,
        'active': _active,
        'salespersonId': _salespersonId,
        if (!widget.isEditing)
          'openingBalance': double.tryParse(_openingBalance.text.trim()) ?? 0,
      };

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final s = context.s;
    final controller = context.read<CustomersController>();
    try {
      if (widget.isEditing) {
        await controller.api.patch(
          '/customers/${widget.customer!.id}',
          body: _body(),
        );
      } else {
        await controller.api.post('/customers', body: _body());
      }
      await controller.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(widget.isEditing ? s.customerUpdated : s.customerCreated),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final customer = widget.customer;
    if (customer == null) return;
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.deleteCustomerQ,
      message: s.customerWillBeRemoved(customer.name),
      confirmLabel: s.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final controller = context.read<CustomersController>();
    try {
      await controller.api.delete('/customers/${customer.id}');
      controller.removeWhere((item) => item.id == customer.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.customerDeleted(customer.name))),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final salespeople = context.watch<SalespeopleController>().salespeople;
    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: s.customerDetails,
              child: Column(
                children: <Widget>[
                  AppTextField(
                    label: s.nameStar,
                    controller: _name,
                    enabled: !_saving,
                    prefixIcon: Icons.person_outline,
                    textCapitalization: TextCapitalization.words,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? s.nameRequired
                        : null,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.customerCode,
                    controller: _code,
                    enabled: !_saving,
                    prefixIcon: Icons.qr_code_2_outlined,
                    helperText: s.codeAutoHint,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.email,
                    controller: _email,
                    enabled: !_saving,
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return null;
                      if (!text.contains('@')) return s.enterValidEmail;
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.phone,
                    controller: _phone,
                    enabled: !_saving,
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.address,
                    controller: _address,
                    enabled: !_saving,
                    maxLines: 2,
                    prefixIcon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.taxId,
                    controller: _taxId,
                    enabled: !_saving,
                    prefixIcon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 14),
                  AppNumberField(
                    label: s.creditLimit,
                    controller: _creditLimit,
                    enabled: !_saving,
                    prefixIcon: Icons.credit_card_outlined,
                  ),
                  if (!widget.isEditing) ...[
                    const SizedBox(height: 14),
                    AppNumberField(
                      label: 'الرصيد الافتتاحى',
                      controller: _openingBalance,
                      enabled: !_saving,
                      prefixIcon: Icons.account_balance_wallet_outlined,
                    ),
                  ],
                  const SizedBox(height: 14),
                  AppSelectField<String?>(
                    label: s.salesperson,
                    value: _salespersonId,
                    enabled: !_saving,
                    prefixIcon: Icons.support_agent_outlined,
                    options: <SelectOption<String?>>[
                      SelectOption<String?>(null, s.unassigned),
                      for (final person in salespeople)
                        SelectOption<String?>(person.id, person.name),
                    ],
                    onChanged: (value) =>
                        setState(() => _salespersonId = value),
                  ),
                  const SizedBox(height: 8),
                  AppSwitchField(
                    label: s.active,
                    value: _active,
                    enabled: !_saving,
                    onChanged: (value) => setState(() => _active = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(false),
                    child: Text(s.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? s.saving : s.save),
                  ),
                ),
              ],
            ),
            if (widget.isEditing) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: Text(s.deleteCustomer),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
