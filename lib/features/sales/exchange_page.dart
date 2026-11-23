import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/common_data.dart';
import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../inventory/serial_widgets.dart';
import '../inventory/tracking_data.dart';
import '../pos/pos_controller.dart';
import '../products/product_picker.dart';
import '../products/products_data.dart';
import 'sales_data.dart';

/// Exchange: the customer brings items back and takes other items. The value of what comes back is used as credit on
/// the new invoice, so only the difference is paid or refunded.
class ExchangePage extends ConsumerWidget {
  const ExchangePage({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(saleDetailProvider(saleId));
    return value.when(
      data: (d) => _ExchangeForm(detail: d),
      loading: () => Scaffold(appBar: AppBar(title: const Text('Exchange')), body: const ListSkeleton(rows: 4)),
      error: (e, _) => Scaffold(appBar: AppBar(title: const Text('Exchange')), body: ErrorState(message: friendlyError(e))),
    );
  }
}

class _NewLine {
  _NewLine(this.product) : qty = TextEditingController(text: product.usesSerials ? '0' : '1');

  final Product product;
  final TextEditingController qty;
  List<String> serials = [];

  void dispose() => qty.dispose();
}

class _ExchangeForm extends ConsumerStatefulWidget {
  const _ExchangeForm({required this.detail});

  final SaleDetail detail;

  @override
  ConsumerState<_ExchangeForm> createState() => _ExchangeFormState();
}

class _ExchangeFormState extends ConsumerState<_ExchangeForm> {
  final Map<String, double> _qty = {};
  final Map<String, String> _condition = {};
  final Map<String, Set<String>> _serials = {};
  final List<_NewLine> _new = [];
  final _reason = TextEditingController();
  final _pay = TextEditingController();
  final String _clientRef = const Uuid().v4();
  String _mode = 'cash';
  String? _accountId;
  bool _payTouched = false;
  bool _saving = false;
  String? _error;

  SaleDetail get d => widget.detail;
  bool get _hasCustomer => d.row.customerId != null;

  @override
  void dispose() {
    _reason.dispose();
    _pay.dispose();
    for (final l in _new) {
      l.dispose();
    }
    super.dispose();
  }

  Map<String, List<String>> get _sold => ref.read(soldUnitsProvider(d.row.id)).valueOrNull ?? const {};

  int get _returnC {
    var t = 0;
    for (final i in d.items) {
      final q = _qty[i.id] ?? 0;
      if (q <= 0) continue;
      t += (i.net * 100 * q / i.qty).round() + (i.tax * 100 * q / i.qty).round();
    }
    return t;
  }

  CartState get _cart => CartState(
        lines: [
          for (final l in _new)
            if (Fmt.parse(l.qty.text) > 0) CartLine(product: l.product, qty: Fmt.parse(l.qty.text), price: l.product.sellingPrice, serials: l.serials),
        ],
      );

  int get _newC => _cart.totals.totalC;

  Future<void> _addNew() async {
    final p = await showProductPicker(context, title: 'Item the customer is taking');
    if (p == null) return;
    final line = _NewLine(p);
    setState(() => _new.add(line));
    if (p.usesSerials) await _pickNewSerials(line);
  }

  Future<void> _pickNewSerials(_NewLine l) async {
    final picked = await showSerialPicker(
      context,
      productId: l.product.id,
      productName: l.product.name,
      branchId: ref.read(currentUserProvider).branchId,
      selected: l.serials,
    );
    if (picked != null) {
      setState(() {
        l.serials = picked;
        l.qty.text = '${picked.length}';
      });
    }
  }

  Future<void> _submit(int diffC) async {
    if (_returnC <= 0) return setState(() => _error = 'Choose the items coming back.');
    if (_new.isEmpty || _newC <= 0) return setState(() => _error = 'Add the items the customer is taking.');
    for (final l in _new) {
      if (l.product.usesSerials && l.serials.length != Fmt.parse(l.qty.text).round()) {
        return setState(() => _error = 'Select the serial/IMEI numbers of ${l.product.name}.');
      }
    }
    final payC = diffC > 0 ? Cents.of(Fmt.parse(_pay.text)) : 0;
    if (diffC > 0 && !_hasCustomer && payC < diffC) {
      return setState(() => _error = 'Walk-in customers must pay the full difference of ${Fmt.money(Cents.toDouble(diffC))}.');
    }
    if ((payC > 0 || (diffC < 0 && !(_hasCustomer && _mode == 'credit'))) && _accountId == null) {
      return setState(() => _error = 'Choose the payment method.');
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await ref.read(salesRepoProvider).createExchange({
        'sale_id': d.row.id,
        'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        'refund_mode': _hasCustomer ? _mode : 'cash',
        'refund_account_id': _accountId,
        'return_items': [
          for (final i in d.items)
            if ((_qty[i.id] ?? 0) > 0)
              {
                'sale_item_id': i.id,
                'quantity': _qty[i.id],
                'condition': _condition[i.id] ?? 'resellable',
                if ((_sold[i.id] ?? const []).isNotEmpty) 'serials': (_serials[i.id] ?? <String>{}).toList(),
              }
        ],
        'new_sale': {
          'client_ref': _clientRef,
          'items': [
            for (final l in _new)
              if (Fmt.parse(l.qty.text) > 0)
                {
                  'product_id': l.product.id,
                  'quantity': Fmt.parse(l.qty.text),
                  'unit_price': l.product.sellingPrice,
                  'discount': 0,
                  if (l.product.usesSerials) 'serials': l.serials,
                }
          ],
        },
        'payments': payC > 0 ? [{'account_id': _accountId, 'amount': Cents.toDouble(payC)}] : [],
      });
      refreshAfterTransaction(ref);
      if (mounted) {
        context.pop();
        showToast(context, 'Exchange done. New invoice ${res['invoice_no']}');
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
    final sold = ref.watch(soldUnitsProvider(d.row.id)).valueOrNull ?? const <String, List<String>>{};
    final accounts = (ref.watch(paymentAccountsProvider).valueOrNull ?? const <PaymentAccount>[]).where((a) => a.isActive).toList();
    if (_accountId == null && accounts.isNotEmpty) _accountId = accounts.firstWhere((a) => a.isCash, orElse: () => accounts.first).id;

    final returnC = _returnC;
    final newC = _newC;
    final diffC = newC - returnC;
    if (!_payTouched) _pay.text = diffC > 0 ? (diffC / 100).toStringAsFixed(2) : '';

    return FormScaffold(
      title: 'Exchange on ${d.row.invoiceNo}',
      saveLabel: 'Complete exchange',
      saving: _saving,
      onSave: () => _submit(diffC),
      children: [
        FormSection('Items coming back', children: [
          for (final i in d.items)
            AppCard(
              margin: const EdgeInsets.only(bottom: 10),
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
                  else if ((sold[i.id] ?? const []).isNotEmpty) ...[
                    for (final s in sold[i.id]!)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(s),
                        value: (_serials[i.id] ?? <String>{}).contains(s),
                        onChanged: (v) => setState(() {
                          final set = _serials.putIfAbsent(i.id, () => <String>{});
                          v == true ? set.add(s) : set.remove(s);
                          _qty[i.id] = set.length.toDouble();
                          _payTouched = false;
                        }),
                      ),
                  ] else
                    Row(
                      children: [
                        IconButton.filledTonal(
                          icon: const Icon(Icons.remove_rounded),
                          onPressed: (_qty[i.id] ?? 0) > 0
                              ? () => setState(() {
                                    _qty[i.id] = ((_qty[i.id] ?? 0) - 1).clamp(0, i.returnable).toDouble();
                                    _payTouched = false;
                                  })
                              : null,
                        ),
                        SizedBox(width: 64, child: Center(child: Text(Fmt.qty(_qty[i.id] ?? 0), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)))),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.add_rounded),
                          onPressed: (_qty[i.id] ?? 0) < i.returnable
                              ? () => setState(() {
                                    _qty[i.id] = ((_qty[i.id] ?? 0) + 1).clamp(0, i.returnable).toDouble();
                                    _payTouched = false;
                                  })
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text('of ${Fmt.qty(i.returnable)}', style: TextStyle(color: c.textMuted, fontSize: 12)),
                      ],
                    ),
                  if ((_qty[i.id] ?? 0) > 0) ...[
                    const SizedBox(height: 8),
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
              ),
            ),
        ]),
        FormSection('Items the customer is taking', children: [
          for (var i = 0; i < _new.length; i++)
            AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('${_new[i].product.name}  |  ${Fmt.money(_new[i].product.sellingPrice)}', style: const TextStyle(fontWeight: FontWeight.w800))),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: c.danger),
                        onPressed: () {
                          final l = _new[i];
                          setState(() {
                            _new.removeAt(i);
                            _payTouched = false;
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) => l.dispose());
                        },
                      ),
                    ],
                  ),
                  if (_new[i].product.usesSerials)
                    AppButton(
                      _new[i].serials.isEmpty ? 'Select units' : '${_new[i].serials.length} unit(s) selected',
                      icon: Icons.qr_code_2_rounded,
                      kind: ButtonKind.secondary,
                      dense: true,
                      onPressed: () => _pickNewSerials(_new[i]),
                    )
                  else
                    AppTextField(
                      controller: _new[i].qty,
                      label: 'Quantity',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                      onChanged: (_) => setState(() => _payTouched = false),
                    ),
                ],
              ),
            ),
          AppButton('Add item', icon: Icons.add_rounded, kind: ButtonKind.secondary, expand: true, onPressed: _addNew),
        ]),
        FormSection('Settlement', children: [
          AppCard(
            color: c.surfaceMuted,
            child: Column(
              children: [
                InfoRow('Value of items coming back', Fmt.money(Cents.toDouble(returnC))),
                InfoRow('New items', Fmt.money(Cents.toDouble(newC))),
                InfoRow(diffC >= 0 ? 'Customer pays' : 'Customer gets back', Fmt.money(Cents.toDouble(diffC.abs())), bold: true, valueColor: diffC >= 0 ? c.text : c.success),
              ],
            ),
          ),
          if (diffC > 0) ...[
            MoneyField(controller: _pay, label: 'Paid now', onChanged: (_) => setState(() => _payTouched = true)),
            if (_hasCustomer) Text('Anything not paid now stays as due on the customer account.', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
          ],
          if (diffC < 0 && _hasCustomer)
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'cash', label: Text('Refund money')), ButtonSegment(value: 'credit', label: Text('Keep as credit'))],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          if ((diffC > 0) || (diffC < 0 && !(_hasCustomer && _mode == 'credit')))
            PickerField<String>(
              label: diffC > 0 ? 'Received in' : 'Refund from',
              value: _accountId,
              options: [for (final a in accounts) PickerOption(a.id, a.name)],
              onChanged: (v) => setState(() => _accountId = v),
            ),
          AppTextField(controller: _reason, label: 'Reason (optional)', maxLines: 2),
          if (_error != null) Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
        ]),
      ],
    );
  }
}
