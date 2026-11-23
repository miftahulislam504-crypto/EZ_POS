import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'installments_data.dart';

/// The plan chosen at the till. Sent to create_installment_sale as the `installment` object.
class InstallmentSetup {
  const InstallmentSetup({
    required this.count,
    required this.frequency,
    required this.firstDue,
    this.serviceCharge = 0,
    this.chargeMode = 'flat',
    this.terms = '',
    this.reminders = true,
    this.guarantors = const [],
    this.custom,
  });

  final int count;
  final String frequency;
  final DateTime firstDue;
  final double serviceCharge;
  final String chargeMode; // flat | percent
  final String terms;
  final bool reminders;
  final List<Guarantor> guarantors;
  final List<({DateTime date, double amount})>? custom;

  double chargeFor(double financed) =>
      chargeMode == 'percent' ? (financed * serviceCharge / 100 * 100).round() / 100 : (serviceCharge * 100).round() / 100;

  double totalPayable(double financed) => financed + chargeFor(financed);

  Map<String, dynamic> toPayload() => {
        'count': custom?.length ?? count,
        'frequency': frequency,
        'first_due_date': Fmt.iso(firstDue),
        'service_charge': serviceCharge,
        'service_charge_mode': chargeMode,
        'terms': terms.trim().isEmpty ? null : terms.trim(),
        'reminders_enabled': reminders,
        'guarantors': [for (final g in guarantors) g.toPayload()],
        if (custom != null) 'custom_schedule': [for (final c in custom!) {'due_date': Fmt.iso(c.date), 'amount': c.amount}],
      };
}

class InstallmentSetupSheet extends ConsumerStatefulWidget {
  const InstallmentSetupSheet({super.key, required this.financed, this.initial});

  /// Amount left after the down payment.
  final double financed;
  final InstallmentSetup? initial;

  static Future<InstallmentSetup?> show(BuildContext context, {required double financed, InstallmentSetup? initial}) {
    return showAppSheet<InstallmentSetup>(
      context,
      title: 'Installment plan',
      maxWidth: 560,
      builder: (_) => InstallmentSetupSheet(financed: financed, initial: initial),
    );
  }

  @override
  ConsumerState<InstallmentSetupSheet> createState() => _InstallmentSetupSheetState();
}

class _CustomRow {
  _CustomRow(this.date, double amount) : amount = TextEditingController(text: amount == 0 ? '' : amount.toStringAsFixed(2));
  DateTime date;
  final TextEditingController amount;
}

class _InstallmentSetupSheetState extends ConsumerState<InstallmentSetupSheet> {
  late final TextEditingController _count;
  late final TextEditingController _charge;
  late final TextEditingController _terms;
  late String _frequency;
  late String _mode;
  late DateTime _first;
  late bool _reminders;
  late List<Guarantor> _guarantors;
  final List<_CustomRow> _custom = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = ref.read(currentUserProvider).business.settings;
    final i = widget.initial;
    _frequency = i?.frequency ?? (s['installment_default_frequency'] as String?) ?? 'monthly';
    if (!kFrequencyLabels.containsKey(_frequency)) _frequency = 'monthly';
    _count = TextEditingController(text: '${i?.count ?? intOf(s['installment_default_count'] ?? 6)}');
    final defaultPct = dbl(s['installment_default_service_percent']);
    _mode = i?.chargeMode ?? (defaultPct > 0 ? 'percent' : 'flat');
    final chargeStart = i?.serviceCharge ?? defaultPct;
    _charge = TextEditingController(text: chargeStart > 0 ? chargeStart.toString() : '');
    _terms = TextEditingController(text: i?.terms ?? (s['installment_agreement_terms'] as String?) ?? '');
    final now = DateTime.now();
    _first = i?.firstDue ?? DateTime(now.year, now.month + 1, now.day);
    _reminders = i?.reminders ?? true;
    _guarantors = [...?i?.guarantors];
    for (final c in i?.custom ?? const <({DateTime date, double amount})>[]) {
      _custom.add(_CustomRow(c.date, c.amount));
    }
  }

  @override
  void dispose() {
    _count.dispose();
    _charge.dispose();
    _terms.dispose();
    for (final c in _custom) {
      c.amount.dispose();
    }
    super.dispose();
  }

  double get _chargeValue => Fmt.parse(_charge.text);
  double get _chargeAmount => _mode == 'percent' ? (widget.financed * _chargeValue / 100 * 100).round() / 100 : _chargeValue;
  double get _payable => widget.financed + _chargeAmount;
  int get _n => (int.tryParse(_count.text.trim()) ?? 0);
  double get _customSum => _custom.fold(0.0, (s, r) => s + Fmt.parse(r.amount.text));

  void _addCustomRow() {
    final base = _custom.isEmpty ? _first : _custom.last.date.add(const Duration(days: 30));
    setState(() => _custom.add(_CustomRow(base, 0)));
  }

  Future<void> _addGuarantor() async {
    final g = await showAppSheet<Guarantor>(context, title: 'Guarantor or reference', builder: (_) => const _GuarantorForm());
    if (g != null) setState(() => _guarantors.add(g));
  }

  void _confirm() {
    final max = intOf(ref.read(currentUserProvider).business.settings['installment_max_count'] ?? 60);
    if (_frequency == 'custom') {
      if (_custom.isEmpty) return setState(() => _error = 'Add the installment dates and amounts.');
      if ((_customSum - _payable).abs() > 0.009) {
        return setState(() => _error = 'The schedule adds up to ${Fmt.money(_customSum)} but ${Fmt.money(_payable)} is payable.');
      }
      if (_custom.any((r) => Fmt.parse(r.amount.text) <= 0)) return setState(() => _error = 'Every installment needs an amount.');
    } else if (_n < 1 || _n > max) {
      return setState(() => _error = 'Number of installments must be between 1 and $max.');
    }
    final sorted = [..._custom]..sort((a, b) => a.date.compareTo(b.date));
    Navigator.pop(
      context,
      InstallmentSetup(
        count: _frequency == 'custom' ? sorted.length : _n,
        frequency: _frequency,
        firstDue: _frequency == 'custom' ? sorted.first.date : _first,
        serviceCharge: _chargeValue,
        chargeMode: _mode,
        terms: _terms.text,
        reminders: _reminders,
        guarantors: _guarantors,
        custom: _frequency == 'custom' ? [for (final r in sorted) (date: r.date, amount: Fmt.parse(r.amount.text))] : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final per = _n > 0 && _frequency != 'custom' ? _payable / _n : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          color: c.primarySoft,
          borderColor: Colors.transparent,
          child: Column(
            children: [
              InfoRow('Amount to finance', Fmt.money(widget.financed)),
              InfoRow('Service charge', Fmt.money(_chargeAmount)),
              InfoRow('Total payable in installments', Fmt.money(_payable), bold: true),
              if (per > 0) InfoRow('Each installment', Fmt.money(per)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PickerField<String>(
          label: 'Frequency',
          value: _frequency,
          options: [for (final e in kFrequencyLabels.entries) PickerOption(e.key, e.value)],
          onChanged: (v) => setState(() {
            _frequency = v ?? 'monthly';
            if (_frequency == 'custom' && _custom.isEmpty) _addCustomRow();
          }),
        ),
        const SizedBox(height: 14),
        if (_frequency != 'custom') ...[
          FieldRow([
            AppTextField(
              controller: _count,
              label: 'Number of installments',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
            ),
            DateField(
              label: 'First due date',
              value: _first,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
              onChanged: (d) => setState(() => _first = d ?? _first),
            ),
          ]),
        ] else ...[
          Text('Dates and amounts', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: c.textMuted)),
          const SizedBox(height: 8),
          for (var i = 0; i < _custom.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: DateField(
                      label: 'Date ${i + 1}',
                      value: _custom[i].date,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                      onChanged: (d) => setState(() => _custom[i].date = d ?? _custom[i].date),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(flex: 4, child: MoneyField(controller: _custom[i].amount, label: 'Amount', onChanged: (_) => setState(() {}))),
                  Padding(
                    padding: const EdgeInsets.only(top: 26),
                    child: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _custom.removeAt(i).amount.dispose()),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              AppButton('Add installment', icon: Icons.add_rounded, kind: ButtonKind.secondary, dense: true, onPressed: _addCustomRow),
              const Spacer(),
              Text(
                'Entered ${Fmt.money(_customSum)}',
                style: context.text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: (_customSum - _payable).abs() <= 0.009 ? c.success : c.warning,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        FieldRow([
          MoneyField(controller: _charge, label: _mode == 'percent' ? 'Service charge (percent)' : 'Service charge', showSymbol: _mode != 'percent', onChanged: (_) => setState(() {})),
          PickerField<String>(
            label: 'Charge type',
            value: _mode,
            options: const [PickerOption('flat', 'Fixed amount'), PickerOption('percent', 'Percent of financed amount')],
            onChanged: (v) => setState(() => _mode = v ?? 'flat'),
          ),
        ]),
        const SizedBox(height: 16),
        SectionHeader(
          'Guarantors and references',
          subtitle: 'Optional. Keep NID copies in the customer profile.',
          trailing: AppButton('Add', icon: Icons.person_add_alt_1_rounded, kind: ButtonKind.secondary, dense: true, onPressed: _addGuarantor),
        ),
        if (_guarantors.isEmpty)
          Text('No guarantor added.', style: context.text.bodySmall?.copyWith(color: c.textMuted))
        else
          for (var i = 0; i < _guarantors.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(_guarantors[i].name, size: 36),
              title: Text(_guarantors[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                _guarantors[i].relationship,
                _guarantors[i].phone,
              ].whereType<String>().where((s) => s.isNotEmpty).join('  |  ')),
              trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _guarantors.removeAt(i))),
            ),
        const SizedBox(height: 12),
        AppTextField(controller: _terms, label: 'Terms and conditions', hint: 'Printed on the installment agreement', maxLines: 3),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _reminders,
          onChanged: (v) => setState(() => _reminders = v),
          title: const Text('Send reminders for this plan', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Due date and overdue reminders'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 12),
        AppButton('Use this plan', expand: true, onPressed: _confirm),
      ],
    );
  }
}

class _GuarantorForm extends StatefulWidget {
  const _GuarantorForm();

  @override
  State<_GuarantorForm> createState() => _GuarantorFormState();
}

class _GuarantorFormState extends State<_GuarantorForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _relation = TextEditingController();
  final _nid = TextEditingController();
  String _kind = 'guarantor';
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _relation, _nid]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickerField<String>(
          label: 'Type',
          value: _kind,
          options: const [
            PickerOption('guarantor', 'Guarantor'),
            PickerOption('reference', 'Reference person'),
            PickerOption('emergency', 'Emergency contact'),
          ],
          onChanged: (v) => setState(() => _kind = v ?? 'guarantor'),
        ),
        const SizedBox(height: 14),
        AppTextField(controller: _name, label: 'Name', textCapitalization: TextCapitalization.words),
        const SizedBox(height: 14),
        FieldRow([
          AppTextField(controller: _phone, label: 'Mobile number', keyboardType: TextInputType.phone),
          AppTextField(controller: _relation, label: 'Relationship to customer'),
        ]),
        const SizedBox(height: 14),
        AppTextField(controller: _address, label: 'Address', maxLines: 2),
        const SizedBox(height: 14),
        AppTextField(controller: _nid, label: 'NID number (optional)', keyboardType: TextInputType.number),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: context.colors.danger))),
        const SizedBox(height: 16),
        AppButton('Add', expand: true, onPressed: () {
          if (_name.text.trim().isEmpty) return setState(() => _error = 'Enter a name.');
          Navigator.pop(
            context,
            Guarantor(
              kind: _kind,
              name: _name.text.trim(),
              phone: nonEmpty(_phone.text),
              address: nonEmpty(_address.text),
              relationship: nonEmpty(_relation.text),
              nid: nonEmpty(_nid.text),
            ),
          );
        }),
      ],
    );
  }
}
