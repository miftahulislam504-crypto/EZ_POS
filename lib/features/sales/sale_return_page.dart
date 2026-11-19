import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/common_data.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'sales_data.dart';

class SaleReturnPage extends ConsumerWidget {
  const SaleReturnPage({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(saleDetailProvider(saleId));
    return value.when(
      data: (d) => _ReturnForm(detail: d),
      loading: () => Scaffold(appBar: AppBar(title: const Text('Return items')), body: const ListSkeleton(rows: 4)),
      error: (e, _) => Scaffold(appBar: AppBar(title: const Text('Return items')), body: ErrorState(message: friendlyError(e))),
    );
  }
}

class _ReturnForm extends ConsumerStatefulWidget {
  const _ReturnForm({required this.detail});

  final SaleDetail detail;

  @override
  ConsumerState<_ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends ConsumerState<_ReturnForm> {
  final Map<String, double> _qty = {};
  final Map<String, String> _condition = {};
  final _reason = TextEditingController();
  String _mode = 'cash';
  String? _accountId;
  bool _saving = false;
  String? _error;

  SaleDetail get d => widget.detail;
  bool get _hasCustomer => d.row.customerId != null;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int get _totalC {
    var t = 0;
    for (final i in d.items) {
      final q = _qty[i.id] ?? 0;
      if (q <= 0) continue;
      t += (i.net * 100 * q / i.qty).round() + (i.tax * 100 * q / i.qty).round();
    }
    return t;
  }

  Future<void> _submit() async {
    final totalC = _totalC;
    if (totalC <= 0) {
      setState(() => _error = 'Choose at least one item to return.');
      return;
    }
    final applyC = _hasCustomer ? (d.row.due * 100).round().clamp(0, totalC).toInt() : 0;
    final mode = _hasCustomer ? _mode : 'cash';
    final refundC = mode == 'cash' ? totalC - applyC : 0;
    if (refundC > 0 && _accountId == null) {
      setState(() => _error = 'Choose the payment method used for the refund.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref.read(salesRepoProvider).createReturn({
        'sale_id': d.row.id,
        'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        'refund_mode': mode,
        'refund_account_id': refundC > 0 ? _accountId : null,
        'items': [
          for (final i in d.items)
            if ((_qty[i.id] ?? 0) > 0) {'sale_item_id': i.id, 'quantity': _qty[i.id], 'condition': _condition[i.id] ?? 'resellable'}
        ],
      });
      refreshAfterTransaction(ref);
      if (mounted) {
        context.pop();
        showToast(context, 'Return recorded');
      }
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
    final accounts = (ref.watch(paymentAccountsProvider).valueOrNull ?? const <PaymentAccount>[]).where((a) => a.isActive).toList();
    if (_accountId == null && accounts.isNotEmpty) _accountId = accounts.firstWhere((a) => a.isCash, orElse: () => accounts.first).id;

    final totalC = _totalC;
    final applyC = _hasCustomer ? (d.row.due * 100).round().clamp(0, totalC).toInt() : 0;
    final mode = _hasCustomer ? _mode : 'cash';
    final refundC = mode == 'cash' ? totalC - applyC : 0;
    final creditC = mode == 'credit' ? totalC - applyC : 0;

    return FormScaffold(
      title: 'Return from ${d.row.invoiceNo}',
      saveLabel: 'Record return',
      saving: _saving,
      onSave: _submit,
      children: [
        const SizedBox(height: 6),
        for (final i in d.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(i.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                      Text('Sold ${Fmt.qty(i.qty)}', style: TextStyle(color: c.textMuted, fontSize: 12)),
                    ],
                  ),
                  if (i.returnable <= 0.0001)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text('Already fully returned', style: TextStyle(color: c.textMuted)))
                  else ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          icon: const Icon(Icons.remove_rounded),
                          onPressed: (_qty[i.id] ?? 0) > 0 ? () => setState(() => _qty[i.id] = ((_qty[i.id] ?? 0) - 1).clamp(0, i.returnable).toDouble()) : null,
                        ),
                        SizedBox(width: 64, child: Center(child: Text(Fmt.qty(_qty[i.id] ?? 0), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)))),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.add_rounded),
                          onPressed: (_qty[i.id] ?? 0) < i.returnable ? () => setState(() => _qty[i.id] = ((_qty[i.id] ?? 0) + 1).clamp(0, i.returnable).toDouble()) : null,
                        ),
                        const SizedBox(width: 8),
                        Text('of ${Fmt.qty(i.returnable)} returnable', style: TextStyle(color: c.textMuted, fontSize: 12)),
                      ],
                    ),
                    if ((_qty[i.id] ?? 0) > 0) ...[
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, children: [
                        for (final cnd in const [('resellable', 'Resellable'), ('damaged', 'Damaged'), ('inspection', 'Needs inspection')])
                          ChoiceChip(
                            label: Text(cnd.$2),
                            selected: (_condition[i.id] ?? 'resellable') == cnd.$1,
                            onSelected: (_) => setState(() => _condition[i.id] = cnd.$1),
                          ),
                      ]),
                    ],
                  ],
                ],
              ),
            ),
          ),
        FormSection('Refund', children: [
          if (_hasCustomer)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Refund money')),
                ButtonSegment(value: 'credit', label: Text('Keep as credit')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            )
          else
            Text('Walk-in sale: the full value is refunded.', style: TextStyle(color: c.textMuted)),
          if (refundC > 0)
            PickerField<String>(
              label: 'Refund from',
              value: _accountId,
              options: [for (final a in accounts) PickerOption(a.id, a.name)],
              onChanged: (v) => setState(() => _accountId = v),
            ),
          AppTextField(controller: _reason, label: 'Reason (optional)', hint: 'Faulty, wrong item, changed mind...', maxLines: 2),
        ]),
        const SizedBox(height: 18),
        AppCard(
          child: Column(
            children: [
              InfoRow('Return value', Fmt.money(Cents.toDouble(totalC)), bold: true),
              if (applyC > 0) InfoRow('Reduces invoice due', Fmt.money(Cents.toDouble(applyC))),
              if (refundC > 0) InfoRow('Refund to customer', Fmt.money(Cents.toDouble(refundC)), valueColor: c.success),
              if (creditC > 0) InfoRow('Added to customer credit', Fmt.money(Cents.toDouble(creditC)), valueColor: c.success),
            ],
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
      ],
    );
  }
}
