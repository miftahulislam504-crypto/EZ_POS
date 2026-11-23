import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/common_data.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'installments_data.dart';

/// Collects money on a plan. Returns the server result (receipt number, allocated amount) or null.
Future<Map<String, dynamic>?> showCollectInstallment(BuildContext context, {required String planId, double? suggested, String? itemId}) {
  return showAppSheet<Map<String, dynamic>>(
    context,
    title: 'Collect installment',
    maxWidth: 520,
    builder: (_) => _CollectForm(planId: planId, suggested: suggested, itemId: itemId),
  );
}

class _CollectForm extends ConsumerStatefulWidget {
  const _CollectForm({required this.planId, this.suggested, this.itemId});

  final String planId;
  final double? suggested;
  final String? itemId;

  @override
  ConsumerState<_CollectForm> createState() => _CollectFormState();
}

class _CollectFormState extends ConsumerState<_CollectForm> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  final String _clientRef = const Uuid().v4();
  String? _accountId;
  bool _pickItems = false;
  late final Set<String> _items = {if (widget.itemId != null) widget.itemId!};
  bool _saving = false;
  bool _amountSet = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(PlanDetail d) async {
    final amount = Fmt.parse(_amount.text);
    if (amount <= 0) return setState(() => _error = 'Enter the amount received.');
    if (_accountId == null) return setState(() => _error = 'Choose how the money was received.');
    if (_pickItems && _items.isEmpty) return setState(() => _error = 'Select at least one installment.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await ref.read(installmentsRepoProvider).collect({
        'plan_id': widget.planId,
        'amount': amount,
        'account_id': _accountId,
        'reference': nonEmpty(_reference.text),
        'note': nonEmpty(_note.text),
        'client_ref': _clientRef,
        if (_pickItems) 'item_ids': _items.toList(),
      });
      refreshAfterTransaction(ref);
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final detail = ref.watch(planDetailProvider(widget.planId));
    final accounts = (ref.watch(paymentAccountsProvider).valueOrNull ?? const <PaymentAccount>[]).where((a) => a.isActive).toList();
    if (_accountId == null && accounts.isNotEmpty) _accountId = (accounts.where((a) => a.isCash).firstOrNull ?? accounts.first).id;

    return detail.when(
      loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => ErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(planDetailProvider)),
      data: (d) {
        final today = DateTime.now();
        final open = d.items.where((i) => i.isOpen).toList();
        if (!_amountSet) {
          _amountSet = true;
          final overdue = open.where((i) => i.isOverdueOn(today)).fold<double>(0, (s, i) => s + i.remaining);
          final first = open.isEmpty ? 0.0 : open.first.remaining;
          final v = widget.suggested ?? (overdue > 0 ? overdue : first);
          _amount.text = v > 0 ? v.toStringAsFixed(2) : '';
        }
        final entered = Fmt.parse(_amount.text);
        final selectedDue = open.where((i) => _items.contains(i.id)).fold<double>(0, (s, i) => s + i.remaining);
        final advance = (_pickItems ? entered - selectedDue : entered - d.plan.outstanding);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              color: c.surfaceMuted,
              child: Column(
                children: [
                  InfoRow('Customer', d.plan.customerName),
                  InfoRow('Plan', d.plan.planNo),
                  InfoRow('Outstanding', Fmt.money(d.plan.outstanding), bold: true),
                  if (d.plan.overdueAmount > 0.004) InfoRow('Overdue now', Fmt.money(d.plan.overdueAmount), valueColor: c.danger, bold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MoneyField(controller: _amount, label: 'Amount received', autofocus: true, onChanged: (_) => setState(() {})),
            if (advance > 0.004)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${Fmt.money(advance)} is more than needed and will stay on the customer account as advance.',
                    style: context.text.bodySmall?.copyWith(color: c.warning, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 14),
            PickerField<String>(
              label: 'Received in',
              value: _accountId,
              options: [for (final a in accounts) PickerOption(a.id, a.name)],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 14),
            FieldRow([
              AppTextField(controller: _reference, label: 'Reference (optional)', hint: 'Transaction ID'),
              AppTextField(controller: _note, label: 'Note (optional)'),
            ]),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pickItems,
              onChanged: (v) => setState(() => _pickItems = v),
              title: const Text('Choose installments', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Otherwise the oldest unpaid installments are paid first'),
            ),
            if (_pickItems)
              for (final i in open)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _items.contains(i.id),
                  onChanged: (v) => setState(() {
                    v == true ? _items.add(i.id) : _items.remove(i.id);
                    final sum = open.where((x) => _items.contains(x.id)).fold<double>(0, (s, x) => s + x.remaining);
                    _amount.text = sum > 0 ? sum.toStringAsFixed(2) : '';
                  }),
                  title: Text('#${i.seq}  |  due ${Fmt.date(i.dueDate)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${Fmt.money(i.remaining)} left${i.isOverdueOn(today) ? '  |  overdue' : ''}'),
                ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 16),
            AppButton('Receive ${Fmt.money(entered)}', icon: Icons.check_rounded, expand: true, loading: _saving, onPressed: () => _submit(d)),
          ],
        );
      },
    );
  }
}
