import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import 'suppliers_data.dart';

class SupplierFormPage extends ConsumerWidget {
  const SupplierFormPage({super.key, this.supplierId});

  final String? supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (supplierId == null) return const _SupplierForm();
    final value = ref.watch(supplierProvider(supplierId!));
    return value.when(
      data: (s) => s == null ? const Scaffold(body: EmptyState(icon: Icons.search_off_rounded, title: 'Supplier not found')) : _SupplierForm(supplier: s),
      loading: () => Scaffold(appBar: AppBar(title: const Text('Edit supplier')), body: const ListSkeleton(rows: 4)),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorState(message: friendlyError(e))),
    );
  }
}

class _SupplierForm extends ConsumerStatefulWidget {
  const _SupplierForm({this.supplier});

  final Supplier? supplier;

  @override
  ConsumerState<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends ConsumerState<_SupplierForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _contact = TextEditingController(text: widget.supplier?.contactPerson ?? '');
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _alt = TextEditingController(text: widget.supplier?.altPhone ?? '');
  late final _email = TextEditingController(text: widget.supplier?.email ?? '');
  late final _address = TextEditingController(text: widget.supplier?.address ?? '');
  late final _type = TextEditingController(text: widget.supplier?.businessType ?? '');
  late final _notes = TextEditingController(text: widget.supplier?.notes ?? '');
  final _opening = TextEditingController();
  bool _openingIsAdvance = false;
  late bool _active = widget.supplier?.isActive ?? true;
  bool _saving = false;

  bool get _isEdit => widget.supplier != null;

  @override
  void dispose() {
    for (final c in [_name, _contact, _phone, _alt, _email, _address, _type, _notes, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(supplierRepoProvider);
      if (_isEdit) {
        await repo.update(widget.supplier!.id, {
          'name': _name.text.trim(),
          'contact_person': nonEmpty(_contact.text),
          'phone': nonEmpty(_phone.text),
          'alt_phone': nonEmpty(_alt.text),
          'email': nonEmpty(_email.text),
          'address': nonEmpty(_address.text),
          'business_type': nonEmpty(_type.text),
          'notes': nonEmpty(_notes.text),
          'is_active': _active,
        });
      } else {
        final opening = Fmt.parse(_opening.text);
        await repo.create({
          'name': _name.text.trim(),
          'contact_person': _contact.text.trim(),
          'phone': _phone.text.trim(),
          'alt_phone': _alt.text.trim(),
          'email': _email.text.trim(),
          'address': _address.text.trim(),
          'business_type': _type.text.trim(),
          'notes': _notes.text.trim(),
          'opening_balance': _openingIsAdvance ? -opening : opening,
        });
      }
      refreshAfterTransaction(ref);
      if (mounted) {
        context.pop();
        showToast(context, _isEdit ? 'Supplier updated' : 'Supplier added');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FormScaffold(
      title: _isEdit ? 'Edit supplier' : 'New supplier',
      formKey: _formKey,
      saving: _saving,
      onSave: _save,
      saveLabel: _isEdit ? 'Save changes' : 'Add supplier',
      children: [
        FormSection('Supplier', children: [
          AppTextField(controller: _name, label: 'Business or supplier name', validator: Validators.required('Name'), textCapitalization: TextCapitalization.words),
          FieldRow([
            AppTextField(controller: _contact, label: 'Contact person', textCapitalization: TextCapitalization.words),
            AppTextField(controller: _type, label: 'Business type', hint: 'Wholesaler, importer...'),
          ]),
        ]),
        FormSection('Contact', children: [
          FieldRow([
            AppTextField(controller: _phone, label: 'Mobile number', keyboardType: TextInputType.phone, validator: Validators.optionalPhone),
            AppTextField(controller: _alt, label: 'Alternative number', keyboardType: TextInputType.phone, validator: Validators.optionalPhone),
          ]),
          AppTextField(controller: _email, label: 'Email', keyboardType: TextInputType.emailAddress, validator: Validators.optionalEmail),
          AppTextField(controller: _address, label: 'Address', maxLines: 2),
          AppTextField(controller: _notes, label: 'Notes', maxLines: 3),
        ]),
        if (!_isEdit)
          FormSection('Opening balance', subtitle: 'Use this when you already owe the supplier, or paid in advance, from before EZ POS.', children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('We owe supplier')),
                ButtonSegment(value: true, label: Text('Advance paid')),
              ],
              selected: {_openingIsAdvance},
              onSelectionChanged: (s) => setState(() => _openingIsAdvance = s.first),
            ),
            MoneyField(controller: _opening, label: 'Amount', validator: Validators.nonNegative('Amount')),
          ])
        else ...[
          FormSection('Status', children: [
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: _active, onChanged: (v) => setState(() => _active = v)),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Balances change through purchases and payments, so they cannot be edited here.', style: TextStyle(color: c.textMuted)),
          ),
        ],
      ],
    );
  }
}
