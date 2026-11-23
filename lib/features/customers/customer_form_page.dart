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
import 'customers_data.dart';

class CustomerFormPage extends ConsumerWidget {
  const CustomerFormPage({super.key, this.customerId});

  final String? customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (customerId == null) return const _CustomerForm();
    final value = ref.watch(customerProvider(customerId!));
    return value.when(
      data: (c) => c == null ? const Scaffold(body: EmptyState(icon: Icons.search_off_rounded, title: 'Customer not found')) : _CustomerForm(customer: c),
      loading: () => Scaffold(appBar: AppBar(title: const Text('Edit customer')), body: const ListSkeleton(rows: 4)),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorState(message: friendlyError(e))),
    );
  }
}

class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({this.customer});

  final Customer? customer;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final _alt = TextEditingController(text: widget.customer?.altPhone ?? '');
  late final _email = TextEditingController(text: widget.customer?.email ?? '');
  late final _present = TextEditingController(text: widget.customer?.presentAddress ?? '');
  late final _permanent = TextEditingController(text: widget.customer?.permanentAddress ?? '');
  late final _nid = TextEditingController(text: widget.customer?.nid ?? '');
  late final _occupation = TextEditingController(text: widget.customer?.occupation ?? '');
  late final _notes = TextEditingController(text: widget.customer?.notes ?? '');
  late final _workplace = TextEditingController(text: widget.customer?.workplace ?? '');
  late final _emergencyName = TextEditingController(text: widget.customer?.emergencyName ?? '');
  late final _emergencyPhone = TextEditingController(text: widget.customer?.emergencyPhone ?? '');
  late bool _reminders = widget.customer?.remindersEnabled ?? true;
  final _opening = TextEditingController();
  late String _group = widget.customer?.group ?? 'regular';
  late DateTime? _birth = widget.customer?.birthDate;
  bool _openingIsAdvance = false;
  bool _sameAddress = false;
  bool _saving = false;

  bool get _isEdit => widget.customer != null;

  @override
  void dispose() {
    for (final c in [_name, _phone, _alt, _email, _present, _permanent, _nid, _occupation, _notes, _opening, _workplace, _emergencyName, _emergencyPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final permanent = _sameAddress ? _present.text : _permanent.text;
      final repo = ref.read(customerRepoProvider);
      if (_isEdit) {
        await repo.update(widget.customer!.id, {
          'name': _name.text.trim(),
          'phone': nonEmpty(_phone.text),
          'alt_phone': nonEmpty(_alt.text),
          'email': nonEmpty(_email.text),
          'present_address': nonEmpty(_present.text),
          'permanent_address': nonEmpty(permanent),
          'nid_number': nonEmpty(_nid.text),
          'birth_date': _birth == null ? null : Fmt.iso(_birth!),
          'occupation': nonEmpty(_occupation.text),
          'workplace': nonEmpty(_workplace.text),
          'emergency_contact_name': nonEmpty(_emergencyName.text),
          'emergency_contact_phone': nonEmpty(_emergencyPhone.text),
          'reminders_enabled': _reminders,
          'customer_group': _group,
          'notes': nonEmpty(_notes.text),
        });
      } else {
        final opening = Fmt.parse(_opening.text);
        await repo.create({
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'alt_phone': _alt.text.trim(),
          'email': _email.text.trim(),
          'present_address': _present.text.trim(),
          'permanent_address': permanent.trim(),
          'nid_number': _nid.text.trim(),
          'birth_date': _birth == null ? null : Fmt.iso(_birth!),
          'occupation': _occupation.text.trim(),
          'workplace': _workplace.text.trim(),
          'emergency_contact_name': _emergencyName.text.trim(),
          'emergency_contact_phone': _emergencyPhone.text.trim(),
          'reminders_enabled': _reminders,
          'customer_group': _group,
          'notes': _notes.text.trim(),
          'opening_balance': _openingIsAdvance ? -opening : opening,
        });
      }
      refreshAfterTransaction(ref);
      if (mounted) {
        context.pop();
        showToast(context, _isEdit ? 'Customer updated' : 'Customer added');
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
      title: _isEdit ? 'Edit customer' : 'New customer',
      formKey: _formKey,
      saving: _saving,
      onSave: _save,
      saveLabel: _isEdit ? 'Save changes' : 'Add customer',
      children: [
        FormSection('Contact', children: [
          AppTextField(controller: _name, label: 'Full name', validator: Validators.required('Name'), textCapitalization: TextCapitalization.words),
          FieldRow([
            AppTextField(controller: _phone, label: 'Mobile number', keyboardType: TextInputType.phone, validator: Validators.optionalPhone, hint: '01XXXXXXXXX'),
            AppTextField(controller: _alt, label: 'Alternative number', keyboardType: TextInputType.phone, validator: Validators.optionalPhone),
          ]),
          AppTextField(controller: _email, label: 'Email (optional)', keyboardType: TextInputType.emailAddress, validator: Validators.optionalEmail),
          PickerField<String>(
            label: 'Customer group',
            value: _group,
            options: const [
              PickerOption('regular', 'Regular'),
              PickerOption('wholesale', 'Wholesale'),
              PickerOption('vip', 'VIP'),
              PickerOption('corporate', 'Corporate'),
              PickerOption('custom', 'Custom'),
            ],
            onChanged: (v) => setState(() => _group = v ?? 'regular'),
          ),
        ]),
        FormSection('Address', children: [
          AppTextField(controller: _present, label: 'Present address', maxLines: 2, onChanged: (_) => setState(() {})),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Permanent address is the same'),
            value: _sameAddress,
            onChanged: (v) => setState(() => _sameAddress = v),
          ),
          if (!_sameAddress) AppTextField(controller: _permanent, label: 'Permanent address', maxLines: 2),
        ]),
        FormSection('Personal details', subtitle: 'Optional. Collect identity details only with the customer\'s consent.', children: [
          FieldRow([
            AppTextField(controller: _nid, label: 'NID number', keyboardType: TextInputType.number),
            AppTextField(controller: _occupation, label: 'Occupation'),
          ]),
          DateField(label: 'Date of birth', value: _birth, allowClear: true, lastDate: DateTime.now(), firstDate: DateTime(1920), onChanged: (d) => setState(() => _birth = d)),
          AppTextField(controller: _notes, label: 'Notes', maxLines: 3, hint: 'Special instructions'),
        ]),
        FormSection('Installment details', subtitle: 'Used when this customer buys on installment. Guarantors are added on each installment sale.', children: [
          AppTextField(controller: _workplace, label: 'Workplace or business', hint: 'Employer, shop or institution'),
          FieldRow([
            AppTextField(controller: _emergencyName, label: 'Emergency contact name', textCapitalization: TextCapitalization.words),
            AppTextField(controller: _emergencyPhone, label: 'Emergency contact number', keyboardType: TextInputType.phone, validator: Validators.optionalPhone),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Send installment reminders', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Turn off for customers who should not receive due date or overdue reminders.'),
            value: _reminders,
            onChanged: (v) => setState(() => _reminders = v),
          ),
          Text(_isEdit ? 'NID copies and agreements are added from the customer profile (Documents).' : 'After saving, open the customer profile to attach NID copies and other documents.', style: TextStyle(color: c.textMuted)),
        ]),
        if (!_isEdit)
          FormSection('Opening balance', subtitle: 'Use this when the customer already owes you, or has paid in advance, from before EZ POS.', children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Customer owes us')),
                ButtonSegment(value: true, label: Text('Advance received')),
              ],
              selected: {_openingIsAdvance},
              onSelectionChanged: (s) => setState(() => _openingIsAdvance = s.first),
            ),
            MoneyField(controller: _opening, label: 'Amount', validator: Validators.nonNegative('Amount')),
          ])
        else
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text('Balances change through sales, payments and returns, so they cannot be edited here.', style: TextStyle(color: c.textMuted)),
          ),
      ],
    );
  }
}
