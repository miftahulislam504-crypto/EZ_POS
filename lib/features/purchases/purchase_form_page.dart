import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/common_data.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/barcode_scanner_page.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../products/products_data.dart';
import '../products/products_tab.dart';
import 'purchases_data.dart';

class _Line {
  _Line(this.product, {double qty = 1, double? cost})
      : qty = TextEditingController(text: Fmt.qty(qty)),
        cost = TextEditingController(text: (cost ?? product.purchasePrice).toStringAsFixed(2)),
        discount = TextEditingController();

  final Product product;
  final TextEditingController qty;
  final TextEditingController cost;
  final TextEditingController discount;

  int get totalC {
    final gross = ((Fmt.parse(qty.text) * 1000).round() * Cents.of(Fmt.parse(cost.text)) + 500) ~/ 1000;
    final t = gross - Cents.of(Fmt.parse(discount.text));
    return t < 0 ? 0 : t;
  }

  void dispose() {
    qty.dispose();
    cost.dispose();
    discount.dispose();
  }
}

class _PayLine {
  _PayLine(this.accountId, String text) : controller = TextEditingController(text: text);
  String accountId;
  final TextEditingController controller;
}

class PurchaseFormPage extends ConsumerStatefulWidget {
  const PurchaseFormPage({super.key, this.supplierId});

  final String? supplierId;

  @override
  ConsumerState<PurchaseFormPage> createState() => _PurchaseFormPageState();
}

class _PurchaseFormPageState extends ConsumerState<PurchaseFormPage> {
  final List<_Line> _lines = [];
  final List<_PayLine> _pays = [];
  final _invoiceNo = TextEditingController();
  final _discount = TextEditingController();
  final _tax = TextEditingController();
  final _other = TextEditingController();
  final _note = TextEditingController();
  final String _clientRef = const Uuid().v4();
  String? _supplierId;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _supplierId = widget.supplierId;
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    for (final p in _pays) {
      p.controller.dispose();
    }
    for (final c in [_invoiceNo, _discount, _tax, _other, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _subtotalC => _lines.fold(0, (s, l) => s + l.totalC);
  int get _totalC {
    final t = _subtotalC - Cents.of(Fmt.parse(_discount.text)) + Cents.of(Fmt.parse(_tax.text)) + Cents.of(Fmt.parse(_other.text));
    return t < 0 ? 0 : t;
  }

  int get _paidC => _pays.fold(0, (s, p) => s + Cents.of(Fmt.parse(p.controller.text)));

  Future<void> _addProduct() async {
    final p = await showAppSheet<Product>(context, title: 'Add product', maxWidth: 560, builder: (_) => const _PurchaseProductPicker());
    if (p == null) return;
    final existing = _lines.where((l) => l.product.id == p.id).firstOrNull;
    setState(() {
      if (existing != null) {
        existing.qty.text = Fmt.qty(Fmt.parse(existing.qty.text) + 1);
      } else {
        _lines.add(_Line(p));
      }
    });
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context, title: 'Scan product');
    if (code == null || !mounted) return;
    final p = await ref.read(productRepoProvider).findByCode(code);
    if (!mounted) return;
    if (p == null) {
      showToast(context, 'No product found for "$code".', error: true);
      return;
    }
    setState(() {
      final existing = _lines.where((l) => l.product.id == p.id).firstOrNull;
      if (existing != null) {
        existing.qty.text = Fmt.qty(Fmt.parse(existing.qty.text) + 1);
      } else {
        _lines.add(_Line(p));
      }
    });
  }

  Future<void> _save(List<PaymentAccount> accounts) async {
    if (_supplierId == null) {
      setState(() => _error = 'Select a supplier.');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }
    for (final l in _lines) {
      if (Fmt.parse(l.qty.text) <= 0) {
        setState(() => _error = 'Enter a quantity for ${l.product.name}.');
        return;
      }
    }
    if (_paidC > _totalC) {
      setState(() => _error = 'Payment is more than the purchase total.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final res = await ref.read(purchaseRepoProvider).create({
        'supplier_id': _supplierId,
        'supplier_invoice_no': _invoiceNo.text.trim().isEmpty ? null : _invoiceNo.text.trim(),
        'purchase_date': Fmt.iso(_date),
        'discount': Fmt.parse(_discount.text),
        'tax_amount': Fmt.parse(_tax.text),
        'other_charges': Fmt.parse(_other.text),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'client_ref': _clientRef,
        'items': [
          for (final l in _lines)
            {'product_id': l.product.id, 'quantity': Fmt.parse(l.qty.text), 'unit_cost': Fmt.parse(l.cost.text), 'discount': Fmt.parse(l.discount.text)}
        ],
        'payments': [
          for (final p in _pays)
            if (Fmt.parse(p.controller.text) > 0) {'account_id': p.accountId, 'amount': Fmt.parse(p.controller.text)}
        ],
      });
      refreshAfterTransaction(ref);
      if (mounted) {
        context.pushReplacement('/purchases/${res['id']}');
        showToast(context, 'Purchase ${res['purchase_no']} recorded and stock updated');
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
    final suppliers = ref.watch(supplierOptionsProvider).valueOrNull ?? const <PartyOption>[];
    final accounts = (ref.watch(paymentAccountsProvider).valueOrNull ?? const <PaymentAccount>[]).where((a) => a.isActive).toList();
    final totalC = _totalC;
    final dueC = totalC - _paidC;

    return FormScaffold(
      title: 'New purchase',
      saveLabel: 'Save purchase',
      saving: _saving,
      onSave: () => _save(accounts),
      maxWidth: 900,
      children: [
        FormSection('Supplier', children: [
          FieldRow([
            PickerField<String>(
              label: 'Supplier',
              hint: 'Select supplier',
              value: _supplierId,
              searchable: true,
              options: [for (final s in suppliers) PickerOption(s.id, s.name)],
              onChanged: (v) => setState(() => _supplierId = v),
            ),
            DateField(label: 'Purchase date', value: _date, lastDate: DateTime.now().add(const Duration(days: 1)), onChanged: (d) => setState(() => _date = d ?? _date)),
          ]),
          AppTextField(controller: _invoiceNo, label: 'Supplier invoice number', hint: 'Optional'),
        ]),
        FormSection('Products', children: [
          if (_lines.isEmpty) Text('No products added yet.', style: TextStyle(color: c.textMuted)),
          for (var i = 0; i < _lines.length; i++)
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(_lines[i].product.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.close_rounded, color: c.danger),
                        onPressed: () {
                          final removed = _lines[i];
                          setState(() => _lines.removeAt(i));
                          WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FieldRow([
                    AppTextField(
                      controller: _lines[i].qty,
                      label: 'Quantity${_lines[i].product.unitName == null ? '' : ' (${_lines[i].product.unitName})'}',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                      onChanged: (_) => setState(() {}),
                    ),
                    MoneyField(controller: _lines[i].cost, label: 'Unit cost', onChanged: (_) => setState(() {})),
                    MoneyField(controller: _lines[i].discount, label: 'Discount', onChanged: (_) => setState(() {})),
                  ]),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: Text('Line total  ${Fmt.money(Cents.toDouble(_lines[i].totalC))}', style: const TextStyle(fontWeight: FontWeight.w800))),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(child: AppButton('Add product', icon: Icons.add_rounded, kind: ButtonKind.secondary, onPressed: _addProduct)),
              const SizedBox(width: 10),
              IconButton.filledTonal(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded)),
            ],
          ),
        ]),
        FormSection('Charges', subtitle: 'Discount, VAT and other charges are spread over the items to work out each product\'s true cost.', children: [
          FieldRow([
            MoneyField(controller: _discount, label: 'Purchase discount', onChanged: (_) => setState(() {})),
            MoneyField(controller: _tax, label: 'VAT / tax', onChanged: (_) => setState(() {})),
            MoneyField(controller: _other, label: 'Other charges', onChanged: (_) => setState(() {})),
          ]),
        ]),
        FormSection('Payment', subtitle: 'Leave empty to buy on credit and pay the supplier later.', children: [
          for (var i = 0; i < _pays.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: PickerField<String>(
                    label: 'Method',
                    value: _pays[i].accountId,
                    options: [for (final a in accounts) PickerOption(a.id, a.name)],
                    onChanged: (v) => setState(() => _pays[i].accountId = v ?? _pays[i].accountId),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: MoneyField(controller: _pays[i].controller, label: 'Amount', onChanged: (_) => setState(() {}))),
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: IconButton(
                    icon: Icon(Icons.remove_circle_outline_rounded, color: c.danger),
                    onPressed: () {
                      final removed = _pays[i];
                      setState(() => _pays.removeAt(i));
                      WidgetsBinding.instance.addPostFrameCallback((_) => removed.controller.dispose());
                    },
                  ),
                ),
              ],
            ),
          if (accounts.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in accounts.where((a) => !_pays.any((p) => p.accountId == a.id)).take(4))
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 16),
                  label: Text('Pay with ${a.name}'),
                  onPressed: () => setState(() => _pays.add(_PayLine(a.id, dueC > 0 ? Cents.toDouble(dueC).toStringAsFixed(2) : ''))),
                ),
            ]),
          AppTextField(controller: _note, label: 'Note (optional)', maxLines: 2),
        ]),
        const SizedBox(height: 18),
        AppCard(
          child: Column(
            children: [
              InfoRow('Items total', Fmt.money(Cents.toDouble(_subtotalC))),
              InfoRow('Total', Fmt.money(Cents.toDouble(totalC)), bold: true),
              InfoRow('Paid now', Fmt.money(Cents.toDouble(_paidC))),
              if (dueC > 0) InfoRow('Payable to supplier', Fmt.money(Cents.toDouble(dueC)), bold: true, valueColor: c.danger),
            ],
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
      ],
    );
  }
}

class _PurchaseProductPicker extends ConsumerStatefulWidget {
  const _PurchaseProductPicker();

  @override
  ConsumerState<_PurchaseProductPicker> createState() => _PurchaseProductPickerState();
}

class _PurchaseProductPickerState extends ConsumerState<_PurchaseProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(productsProvider((search: _q, categoryId: null, limit: 40, includeInactive: false)));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(hint: 'Search products', autofocus: true, onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 8),
        value.when(
          data: (items) => items.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No products found')))
              : Column(
                  children: [
                    for (final p in items.where((p) => p.trackStock))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: ProductThumb(url: p.imageUrl, size: 42),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${p.sku ?? ''}  |  In stock ${Fmt.qty(p.stock)}  |  Cost ${Fmt.money(p.purchasePrice)}'),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e))),
        ),
      ],
    );
  }
}
