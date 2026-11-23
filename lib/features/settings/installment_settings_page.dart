import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../installments/installments_data.dart';
import 'settings_data.dart';

/// Defaults for new plans, the reminder schedule and the message templates.
class InstallmentSettingsPage extends ConsumerStatefulWidget {
  const InstallmentSettingsPage({super.key});

  @override
  ConsumerState<InstallmentSettingsPage> createState() => _InstallmentSettingsPageState();
}

class _InstallmentSettingsPageState extends ConsumerState<InstallmentSettingsPage> {
  late final _b = ref.read(currentUserProvider).business;
  late final Map<String, dynamic> _s = _b.settings;
  late final _count = TextEditingController(text: '${intOf(_s['installment_default_count'] ?? 6)}');
  late final _percent = TextEditingController(text: dbl(_s['installment_default_service_percent']) == 0 ? '' : '${dbl(_s['installment_default_service_percent'])}');
  late final _minDown = TextEditingController(text: dbl(_s['installment_min_down_percent']) == 0 ? '' : '${dbl(_s['installment_min_down_percent'])}');
  late final _maxCount = TextEditingController(text: '${intOf(_s['installment_max_count'] ?? 60)}');
  late final _before = TextEditingController(text: _beforeText());
  late final _every = TextEditingController(text: '${intOf(_s['installment_overdue_every_days'] ?? 3)}');
  late final _gap = TextEditingController(text: '${intOf(_s['installment_reminder_gap_days'] ?? 1)}');
  late final _tplBefore = TextEditingController(text: (_s['installment_tpl_before'] as String?) ?? _defBefore);
  late final _tplDue = TextEditingController(text: (_s['installment_tpl_due'] as String?) ?? _defDue);
  late final _tplOver = TextEditingController(text: (_s['installment_tpl_overdue'] as String?) ?? _defOver);
  late final _terms = TextEditingController(text: (_s['installment_agreement_terms'] as String?) ?? '');
  late final _lateFee = TextEditingController(text: (_s['installment_late_fee_note'] as String?) ?? '');
  late String _frequency = (_s['installment_default_frequency'] as String?) ?? 'monthly';
  late bool _onDue = _s['installment_remind_on_due'] != false;
  bool _saving = false;

  static const _defBefore = 'Dear {name}, your installment of {amount} for {plan} is due on {due_date}. Please keep the payment ready. Thank you, {shop}.';
  static const _defDue = 'Dear {name}, your installment of {amount} for {plan} is due today. Please pay at {shop}. Thank you.';
  static const _defOver = 'Dear {name}, your installment of {amount} for {plan} was due on {due_date} and is {days} day(s) overdue. Please pay as soon as possible. {shop}.';

  String _beforeText() {
    final v = _s['installment_remind_before'];
    if (v is List) return v.map((e) => e.toString()).join(', ');
    return '2';
  }

  @override
  void dispose() {
    for (final c in [_count, _percent, _minDown, _maxCount, _before, _every, _gap, _tplBefore, _tplDue, _tplOver, _terms, _lateFee]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final days = <int>[
      for (final p in _before.text.split(RegExp(r'[,\s]+')))
        if (int.tryParse(p) != null && int.parse(p) > 0) int.parse(p),
    ];
    final max = int.tryParse(_maxCount.text.trim()) ?? 60;
    final count = int.tryParse(_count.text.trim()) ?? 6;
    if (count < 1 || count > max) {
      showToast(context, 'Default number of installments must be between 1 and $max.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepoProvider).saveSettings(_b, {
        'installment_default_count': count,
        'installment_default_frequency': _frequency,
        'installment_default_service_percent': Fmt.parse(_percent.text),
        'installment_min_down_percent': Fmt.parse(_minDown.text),
        'installment_max_count': max,
        'installment_remind_before': days,
        'installment_remind_on_due': _onDue,
        'installment_overdue_every_days': int.tryParse(_every.text.trim()) ?? 3,
        'installment_reminder_gap_days': (int.tryParse(_gap.text.trim()) ?? 1).clamp(1, 30),
        'installment_tpl_before': _tplBefore.text.trim(),
        'installment_tpl_due': _tplDue.text.trim(),
        'installment_tpl_overdue': _tplOver.text.trim(),
        'installment_agreement_terms': _terms.text.trim(),
        'installment_late_fee_note': _lateFee.text.trim(),
      });
      ref.invalidate(appUserProvider);
      if (mounted) {
        context.pop();
        showToast(context, 'Installment settings saved');
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
    return FormScaffold(
      title: 'Installment settings',
      saving: _saving,
      onSave: _save,
      children: [
        FormSection('New plans', subtitle: 'Starting values at the checkout. The cashier can change them for each sale.', children: [
          FieldRow([
            AppTextField(controller: _count, label: 'Default number of installments', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            PickerField<String>(
              label: 'Default frequency',
              value: _frequency,
              options: [for (final e in kFrequencyLabels.entries.where((e) => e.key != 'custom')) PickerOption(e.key, e.value)],
              onChanged: (v) => setState(() => _frequency = v ?? 'monthly'),
            ),
          ]),
          FieldRow([
            MoneyField(controller: _percent, label: 'Default service charge (percent)', showSymbol: false),
            MoneyField(controller: _minDown, label: 'Minimum down payment (percent)', showSymbol: false),
          ]),
          AppTextField(controller: _maxCount, label: 'Maximum installments per plan', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
        ]),
        FormSection('Reminders', subtitle: 'Reminders are opened in WhatsApp or the SMS app and logged. Placeholders: {name} {amount} {plan} {due_date} {days} {shop}.', children: [
          AppTextField(controller: _before, label: 'Remind this many days before the due date', hint: '3, 1', helper: 'Separate several days with commas. Leave empty for none.'),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _onDue, onChanged: (v) => setState(() => _onDue = v), title: const Text('Remind on the due date', style: TextStyle(fontWeight: FontWeight.w700))),
          FieldRow([
            AppTextField(controller: _every, label: 'Repeat overdue reminder every (days)', keyboardType: TextInputType.number, helper: '0 turns overdue reminders off'),
            AppTextField(controller: _gap, label: 'Never remind a customer more than once in (days)', keyboardType: TextInputType.number),
          ]),
          AppTextField(controller: _tplBefore, label: 'Message before the due date', maxLines: 3),
          AppTextField(controller: _tplDue, label: 'Message on the due date', maxLines: 3),
          AppTextField(controller: _tplOver, label: 'Overdue message', maxLines: 3),
        ]),
        FormSection('Agreement', subtitle: 'Printed on the installment agreement.', children: [
          AppTextField(controller: _terms, label: 'Terms and conditions', maxLines: 4),
          AppTextField(controller: _lateFee, label: 'Late fee policy (text only)', maxLines: 2, helper: 'Shown on the agreement. Late fees are not charged automatically.'),
        ]),
      ],
    );
  }
}
