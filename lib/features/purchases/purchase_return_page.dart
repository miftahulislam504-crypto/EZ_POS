import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/common_data.dart';
import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'purchases_data.dart';

class _ReturnLine {
  const _ReturnLine({required this.id, required this.productId, required this.name, required this.quantity, required this.returned, required this.lineTotal, required this.tracking});

  final String id;
  final String productId;
  final String name;
  final double quantity;
  final double returned;
  final double lineTotal;
  final String tracking;

  double get returnable => (quantity - returned).clamp(0, double.infinity).toDouble();
  bool get usesSerials => tracking == 'serial' || tracking == 'imei';
  double creditFor(double q) => quantity <= 0 ? 0 : (lineTotal * 100 * q / quantity).round() / 100;
}

class _Source {
  const _Source({required this.purchaseNo, required this.supplier, required this.due, required this.status, required this.lines, required this.serials});

  final String purchaseNo;
  final String supplier;
  final double due;
  final String status;
  final List<_ReturnLine> lines;
  final Map<String, List<String>> serials; // product id -> in-stock units bought on this purchase
}

final _sourceProvider = FutureProvider.autoDispose.family<_Source, String>((ref, id) async {
  final client = ref.watch(supabaseProvider);
  final j = await client.from('purchases').select('*, suppliers(name), purchase_items(*, products(tracking_type))').eq('id', id).single();
  final items = asRows(j['purchase_items']);
  items.sort((a, b) => intOf(a['line_no']).compareTo(intOf(b['line_no'])));
  final units = await client.from('stock_units').select('serial_no, product_id').eq('purchase_id', id).eq('status', 'in_stock');
  final serials = <String, List<String>>{};
  for (final u in units) {
    serials.putIfAbsent(u['product_id'] as String, () => []).add(u['serial_no'] as String);
  }
  return _Source(
    purchaseNo: j['purchase_no'] as String,
    supplier: (j['suppliers'] as Map?)?['name'] as String? ?? '',
    due: dbl(j['due_amount']),
    status: j['status'] as String,
    serials: serials,
    lines: [
      for (final i in items)
        _ReturnLine(
          id: i['id'] as String,
          productId: i['product_id'] as String,
          name: i['product_name'] as String,
          quantity: dbl(i['received_quantity']),
          returned: dbl(i['returned_quantity']),
          lineTotal: dbl(i['line_total']),
          tracking: (i['products'] as Map?)?['tracking_type'] as String? ?? 'none',
        )
    ],
  );
});

/// Send goods back to the supplier. The credit reduces what you owe, or comes back as money.
class PurchaseReturnPage extends ConsumerWidget {
  const PurchaseReturnPage({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(_sourceProvider(purchaseId));
    return value.when(
      data: (s) => _Form(purchaseId: purchaseId, source: s),
      loading: () => Scaffold(appBar: AppBar(title: const Text('Purchase return')), body: const ListSkeleton(rows: 4)),
      error: (e, _) => Scaffold(appBar: AppBar(title: const Text('Purchase return')), body: ErrorState(message: friendlyError(e))),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.purchaseId, required this.source});

  final String purchaseId;
  final _Source source;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final Map<String, double> _qty = {};
  final Map<String, Set<String>> _serials = {};
  final _reason = TextEditingController();
  String _mode = 'credit';
  String? _accountId;
  bool _saving = false;
  String? _error;

  _Source get s => widget.source;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  double get _total => s.lines.fold(0.0, (t, l) => t + l.creditFor(_qty[l.id] ?? 0));

  Future<void> _submit() async {
    final total = _total;
    if (total <= 0) return setState(() => _error = 'Choose the items to return.');
    final apply = total < s.due ? total : s.due;
    final refund = _mode == 'cash' ? total - apply : 0.0;
    if (refund > 0.004 && _accountId == null) return setState(() => _error = 'Choose where the refund is received.');
    for (final l in s.lines) {
      if (l.usesSerials && (_qty[l.id] ?? 0) > 0 && (_serials[l.id]?.length ?? 0) != (_qty[l.id] ?? 0).round()) {
        return setState(() => _error = 'Select the units of ${l.name}.');
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(purchaseRepoProvider).createReturn({
        'purchase_id': widget.purchaseId,
        'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        'refund_mode': _mode,
        'refund_account_id': refund > 0.004 ? _accountId : null,
        'items': [
          for (final l in s.lines)
            if ((_qty[l.id] ?? 0) > 0)
              {'purchase_item_id': l.id, 'quantity': _qty[l.id], if (l.usesSerials) 'serials': (_serials[l.id] ?? <String>{}).toList()}
        ],
      });
      refreshAfterTransaction(ref);
      ref.invalidate(purchaseReturnsProvider(widget.purchaseId));
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
    final total = _total;
    final apply = total < s.due ? total : s.due;
    final refund = _mode == 'cash' ? total - apply : 0.0;
    final advance = _mode == 'credit' ? total - apply : 0.0;

    return FormScaffold(
      title: 'Return to supplier',
      saveLabel: 'Record return',
      saving: _saving,
      onSave: _submit,
      children: [
        Text('${s.purchaseNo}  |  ${s.supplier}', style: context.text.bodyMedium?.copyWith(color: c.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (s.status != 'received')
          Text('Only received purchases can be returned.', style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
        for (final l in s.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(l.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                      Text('Bought ${Fmt.qty(l.quantity)}', style: TextStyle(color: c.textMuted, fontSize: 12)),
                    ],
                  ),
                  if (l.returnable <= 0.0001)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text('Already fully returned', style: TextStyle(color: c.textMuted)))
                  else if (l.usesSerials) ...[
                    const SizedBox(height: 6),
                    Text('Units still in stock from this purchase', style: TextStyle(color: c.textMuted, fontSize: 12)),
                    for (final sn in s.serials[l.productId] ?? const <String>[])
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(sn),
                        value: (_serials[l.id] ?? <String>{}).contains(sn),
                        onChanged: (v) => setState(() {
                          final set = _serials.putIfAbsent(l.id, () => <String>{});
                          v == true ? set.add(sn) : set.remove(sn);
                          _qty[l.id] = set.length.toDouble();
                        }),
                      ),
                  ] else ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          icon: const Icon(Icons.remove_rounded),
                          onPressed: (_qty[l.id] ?? 0) > 0 ? () => setState(() => _qty[l.id] = ((_qty[l.id] ?? 0) - 1).clamp(0, l.returnable).toDouble()) : null,
                        ),
                        SizedBox(width: 64, child: Center(child: Text(Fmt.qty(_qty[l.id] ?? 0), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)))),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.add_rounded),
                          onPressed: (_qty[l.id] ?? 0) < l.returnable ? () => setState(() => _qty[l.id] = ((_qty[l.id] ?? 0) + 1).clamp(0, l.returnable).toDouble()) : null,
                        ),
                        const SizedBox(width: 8),
                        Text('of ${Fmt.qty(l.returnable)} returnable', style: TextStyle(color: c.textMuted, fontSize: 12)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        FormSection('Credit', children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'credit', label: Text('Reduce what I owe')), ButtonSegment(value: 'cash', label: Text('Supplier refunds money'))],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
          if (refund > 0.004)
            PickerField<String>(
              label: 'Refund received in',
              value: _accountId,
              options: [for (final a in accounts) PickerOption(a.id, a.name)],
              onChanged: (v) => setState(() => _accountId = v),
            ),
          AppTextField(controller: _reason, label: 'Reason (optional)', hint: 'Defective, wrong item...', maxLines: 2),
        ]),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            children: [
              InfoRow('Return value', Fmt.money(total), bold: true),
              if (apply > 0.004) InfoRow('Reduces this purchase due', Fmt.money(apply)),
              if (refund > 0.004) InfoRow('Refund to receive', Fmt.money(refund), valueColor: c.success),
              if (advance > 0.004) InfoRow('Kept as credit with supplier', Fmt.money(advance), valueColor: c.success),
            ],
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
      ],
    );
  }
}
