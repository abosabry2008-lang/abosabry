import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/l10n.dart';
import '../../models/supplier.dart';
import '../../state/suppliers_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/section_card.dart';

/// Create / edit form for a supplier.
class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({super.key, this.supplier});

  final Supplier? supplier;

  bool get isEditing => supplier != null;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.supplier?.name ?? '');
  late final TextEditingController _contact =
      TextEditingController(text: widget.supplier?.contact ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.supplier?.email ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.supplier?.phone ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.supplier?.address ?? '');
  late final TextEditingController _taxId =
      TextEditingController(text: widget.supplier?.taxId ?? '');
  late final TextEditingController _paymentTermDays = TextEditingController(
    text: (widget.supplier?.paymentTermDays ?? 30).toString(),
  );
  late final TextEditingController _openingBalance = TextEditingController(text: '0');

  late bool _active = widget.supplier?.active ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _taxId.dispose();
    _paymentTermDays.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  Map<String, dynamic> _body() => <String, dynamic>{
        'name': _name.text.trim(),
        'contact': _contact.text.trim().isEmpty ? null : _contact.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'taxId': _taxId.text.trim().isEmpty ? null : _taxId.text.trim(),
        'paymentTermDays': int.tryParse(_paymentTermDays.text.trim()) ?? 30,
        'active': _active,
        if (!widget.isEditing)
          'openingBalance': double.tryParse(_openingBalance.text.trim()) ?? 0,
      };

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final s = context.s;
    final controller = context.read<SuppliersController>();
    try {
      if (widget.isEditing) {
        await controller.api.patch(
          '/suppliers/${widget.supplier!.id}',
          body: _body(),
        );
      } else {
        await controller.api.post('/suppliers', body: _body());
      }
      await controller.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing ? s.supplierUpdated : s.supplierCreated,
          ),
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
    final supplier = widget.supplier;
    if (supplier == null) return;
    final s = context.s;
    final confirmed = await confirmDialog(
      context,
      title: s.deleteSupplierQ,
      message: s.supplierWillBeRemoved(supplier.name),
      confirmLabel: s.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final controller = context.read<SuppliersController>();
    try {
      await controller.api.delete('/suppliers/${supplier.id}');
      controller.removeWhere((item) => item.id == supplier.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.supplierDeleted(supplier.name))),
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
    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SectionCard(
              title: s.supplierDetails,
              child: Column(
                children: <Widget>[
                  AppTextField(
                    label: s.nameStar,
                    controller: _name,
                    enabled: !_saving,
                    prefixIcon: Icons.business_outlined,
                    textCapitalization: TextCapitalization.words,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? s.nameRequired
                        : null,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: s.contactPerson,
                    controller: _contact,
                    enabled: !_saving,
                    prefixIcon: Icons.person_outline,
                    textCapitalization: TextCapitalization.words,
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
                    label: s.paymentTermDays,
                    controller: _paymentTermDays,
                    enabled: !_saving,
                    decimal: false,
                    prefixIcon: Icons.schedule_outlined,
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
                label: Text(s.deleteSupplier),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
