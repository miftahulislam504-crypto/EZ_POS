import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/common_data.dart';
import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../installments/installment_setup_sheet.dart';
import '../installments/installments_data.dart';
import '../sales/invoice_doc.dart';
import '../sales/sales_data.dart';
import 'customer_picker.dart';
import 'pos_controller.dart';

class SaleResult {
  const SaleResult({
    required this.id,
    required this.invoiceNo,
    required this.total,
    required this.paid,
    required this.due,
    required this.change,
    this.planId,
    this.planNo,
  });

  final String? planId;
  final String? planNo;
  final String id;
  final String invoiceNo;
  final double total;
  final double paid;
  final double due;
  final double change;
}

/// Opens checkout. On success the cart is cleared and the sale confirmation is shown.
Future<void> showCheckout(BuildContext context, WidgetRef ref) async {
  final root = Navigator.of(context, rootNavigator: true).context;
  final result = await showAppSheet<SaleResult>(context, title: 'Checkout', maxWidth: 560, builder: (_) => const _CheckoutForm());
  if (result != null && root.mounted) {
    await showDialog<void>(context: root, barrierDismissible: false, builder: (_) => _SaleSuccessDialog(result: result));
  }
}

class _PayLine {
  _PayLine(this.accountId, String text) : controller = TextEditingController(text: text);

  String accountId;
  final TextEditingController controller;
}

class _CheckoutForm extends ConsumerStatefulWidget {
  const _CheckoutForm();

  @override
  ConsumerState<_CheckoutForm> createState() => _CheckoutFormState();
}

class _CheckoutFormState extends ConsumerState<_CheckoutForm> {
  final List<_PayLine> _lines = [];
  final String _clientRef = const Uuid().v4();
  bool _saving = false;
  String? _error;
  bool _installment = false;
  InstallmentSetup? _setup;

  @override
  void dispose() {
    for (final l in _lines) {
      l.controller.dispose();
    }
    super.dispose();
  }

  ({int applied, int change, bool overNonCash, List<Map<String, dynamic>> payments}) _calc(List<PaymentAccount> accounts, int totalC) {
    var remaining = totalC;
    var applied = 0;
    var change = 0;
    var over = false;
    final payments = <Map<String, dynamic>>[];
    for (final l in _lines) {
      final entered = Cents.of(Fmt.parse(l.controller.text));
      if (entered <= 0) continue;
      final acc = accounts.where((a) => a.id == l.accountId).firstOrNull;
      final take = math.min(entered, remaining);
      if (entered > remaining) {
        if (acc?.isCash ?? false) {
          change += entered - remaining;
        } else {
          over = true;
        }
      }
      if (take > 0) {
        payments.add({'account_id': l.accountId, 'amount': Cents.toDouble(take)});
        applied += take;
        remaining -= take;
      }
    }
    return (applied: applied, change: change, overNonCash: over, payments: payments);
  }

  Future<void> _submit(List<PaymentAccount> accounts) async {
    final cart = ref.read(cartProvider);
    final user = ref.read(currentUserProvider);
    final totals = cart.totals;
    final calc = _calc(accounts, totals.totalC);
    final dueC = totals.totalC - calc.applied;

    if (calc.overNonCash) {
      setState(() => _error = 'A non-cash payment is more than the amount left to pay.');
      return;
    }
    if (_installment) {
      if (cart.customer == null) {
        setState(() => _error = 'Select a customer for an installment sale.');
        return;
      }
      if (dueC <= 0) {
        setState(() => _error = 'The down payment covers the full amount. Switch back to Pay now.');
        return;
      }
      if (_setup == null) {
        setState(() => _error = 'Set up the installment plan first.');
        return;
      }
    } else if (dueC > 0) {
      if (cart.customer == null) {
        setState(() => _error = 'Select a customer to sell the remaining ${Fmt.money(Cents.toDouble(dueC))} on credit.');
        return;
      }
      if (!user.business.allowDueSale || !user.can(Perm.salesDue)) {
        setState(() => _error = 'Credit sales are not allowed. Collect the full amount.');
        return;
      }
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final payload = cart.toPayload(payments: calc.payments, clientRef: _clientRef);
      final Map<String, dynamic> res;
      if (_installment) {
        res = await ref.read(installmentsRepoProvider).createSale({...payload, 'installment': _setup!.toPayload()});
      } else {
        res = await ref.read(salesRepoProvider).create(payload);
      }
      ref.read(cartProvider.notifier).clear();
      refreshAfterTransaction(ref);
      if (mounted) {
        Navigator.pop(
          context,
          SaleResult(
            id: res['id'] as String,
            invoiceNo: res['invoice_no'] as String,
            total: (res['total'] as num).toDouble(),
            paid: (res['paid'] as num).toDouble(),
            due: ((_installment ? res['total_payable'] : res['due']) as num).toDouble(),
            change: Cents.toDouble(calc.change),
            planId: res['plan_id'] as String?,
            planNo: res['plan_no'] as String?,
          ),
        );
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
    final cart = ref.watch(cartProvider);
    final totals = cart.totals;
    final accounts = (ref.watch(paymentAccountsProvider).valueOrNull ?? const <PaymentAccount>[]).where((a) => a.isActive).toList();

    if (_lines.isEmpty && accounts.isNotEmpty) {
      final cash = accounts.firstWhere((a) => a.isCash, orElse: () => accounts.first);
      _lines.add(_PayLine(cash.id, totals.total.toStringAsFixed(2)));
    }

    final calc = _calc(accounts, totals.totalC);
    final dueC = totals.totalC - calc.applied;
    final usedIds = _lines.map((l) => l.accountId).toSet();
    final unused = accounts.where((a) => !usedIds.contains(a.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          color: c.surfaceMuted,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Text('Amount to pay', style: context.text.titleSmall?.copyWith(color: c.textMuted, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  MoneyText(totals.total, style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                ],
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final pick = await showCustomerPicker(context);
                  if (pick != null) ref.read(cartProvider.notifier).setCustomer(pick.customer);
                },
                child: Row(
                  children: [
                    Icon(Icons.person_outline_rounded, size: 18, color: c.textMuted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(cart.customer?.name ?? 'Walk-in customer', style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text('Change', style: TextStyle(color: c.primary, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (ref.watch(currentUserProvider).can(Perm.installmentsCreate)) ...[
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Pay now'), icon: Icon(Icons.payments_outlined)),
              ButtonSegment(value: true, label: Text('Installment'), icon: Icon(Icons.event_repeat_rounded)),
            ],
            selected: {_installment},
            onSelectionChanged: (v) => setState(() {
              _installment = v.first;
              _error = null;
              if (_installment) {
                // start the down payment from zero so the cashier types what the customer actually pays
                for (final l in _lines) {
                  l.controller.text = '';
                }
              } else {
                _setup = null;
              }
            }),
          ),
        ],
        const SizedBox(height: 18),
        Text(_installment ? 'Down payment' : 'Payment', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        for (var i = 0; i < _lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 128,
                  child: PickerField<String>(
                    label: i == 0 ? 'Method' : 'Method ${i + 1}',
                    value: _lines[i].accountId,
                    options: [for (final a in accounts) PickerOption(a.id, a.name)],
                    onChanged: (v) => setState(() => _lines[i].accountId = v ?? _lines[i].accountId),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MoneyField(
                    controller: _lines[i].controller,
                    label: 'Amount',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (_lines.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: IconButton(
                      icon: Icon(Icons.remove_circle_outline_rounded, color: c.danger),
                      onPressed: () {
                        final removed = _lines[i];
                        setState(() => _lines.removeAt(i));
                        WidgetsBinding.instance.addPostFrameCallback((_) => removed.controller.dispose());
                      },
                    ),
                  ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in unused.take(4))
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: Text(a.name),
                onPressed: () {
                  final remaining = math.max(0, totals.totalC - calc.applied);
                  setState(() => _lines.add(_PayLine(a.id, remaining > 0 ? Cents.toDouble(remaining).toStringAsFixed(2) : '')));
                },
              ),
            if (!_installment)
            ActionChip(
              avatar: const Icon(Icons.schedule_rounded, size: 16),
              label: const Text('Pay later (credit)'),
              onPressed: () => setState(() {
                for (final l in _lines) {
                  l.controller.text = '';
                }
              }),
            ),
          ],
        ),
        const SizedBox(height: 18),
        InfoRow('Paid now', Fmt.money(Cents.toDouble(calc.applied))),
        if (calc.change > 0) InfoRow('Change to return', Fmt.money(Cents.toDouble(calc.change)), bold: true, valueColor: c.success),
        if (dueC > 0)
          InfoRow(_installment ? 'To finance' : 'Due (credit)', Fmt.money(Cents.toDouble(dueC)), bold: true, valueColor: c.danger),
        if (_installment && dueC > 0) ...[
          const SizedBox(height: 10),
          AppCard(
            onTap: () async {
              final r = await InstallmentSetupSheet.show(context, financed: Cents.toDouble(dueC), initial: _setup);
              if (r != null) setState(() => _setup = r);
            },
            child: Row(
              children: [
                const IconBadge(Icons.event_repeat_rounded, tone: Tone.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_setup == null ? 'Set up installment plan' : 'Installment plan', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                        _setup == null
                            ? 'Number, dates, service charge and guarantors'
                            : '${_setup!.custom?.length ?? _setup!.count} x ${kFrequencyLabels[_setup!.frequency]}  |  total ${Fmt.money(_setup!.totalPayable(Cents.toDouble(dueC)))}',
                        style: context.text.bodySmall?.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textMuted),
              ],
            ),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
            ),
          ),
        const SizedBox(height: 20),
        AppButton(
          _installment ? 'Complete installment sale' : (dueC > 0 ? 'Complete sale (${Fmt.money(Cents.toDouble(dueC))} due)' : 'Complete sale'),
          icon: Icons.check_rounded,
          expand: true,
          loading: _saving,
          onPressed: accounts.isEmpty ? null : () => _submit(accounts),
        ),
      ],
    );
  }
}

class _SaleSuccessDialog extends ConsumerStatefulWidget {
  const _SaleSuccessDialog({required this.result});

  final SaleResult result;

  @override
  ConsumerState<_SaleSuccessDialog> createState() => _SaleSuccessDialogState();
}

class _SaleSuccessDialogState extends ConsumerState<_SaleSuccessDialog> {
  SaleDetail? _detail;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(salesRepoProvider).detail(widget.result.id);
      if (!mounted) return;
      setState(() => _detail = d);
      final business = ref.read(currentUserProvider).business;
      if (business.autoPrint) await PdfBuilder.printDoc(invoiceDoc(d), business);
    } catch (_) {
      // Printing is optional; the sale itself is already saved.
    }
  }

  Future<void> _run(Future<void> Function(SaleDetail d, Business b) action) async {
    final d = _detail;
    if (d == null) return;
    setState(() => _printing = true);
    try {
      await action(d, ref.read(currentUserProvider).business);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.result;
    return AlertDialog(
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            const IconBadge(Icons.check_rounded, tone: Tone.success, size: 68),
            const SizedBox(height: 16),
            Text('Sale completed', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(r.invoiceNo, style: TextStyle(color: c.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            MoneyText(r.total, style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
            const SizedBox(height: 10),
            if (r.change > 0) StatusPill('Return change ${Fmt.money(r.change)}', tone: Tone.success),
            if (r.planNo != null) StatusPill('Plan ${r.planNo}  |  payable ${Fmt.money(r.due)}', tone: Tone.brand)
            else if (r.due > 0.004) StatusPill('Due ${Fmt.money(r.due)}', tone: Tone.danger),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowAlignment: OverflowBarAlignment.center,
      actionsOverflowButtonSpacing: 8,
      actions: [
        AppButton('Print', icon: Icons.print_outlined, kind: ButtonKind.secondary, dense: true, loading: _printing,
            onPressed: _detail == null ? null : () => _run((d, b) => PdfBuilder.printDoc(invoiceDoc(d), b))),
        AppButton('Share', icon: Icons.ios_share_rounded, kind: ButtonKind.secondary, dense: true,
            onPressed: _detail == null ? null : () => _run((d, b) => PdfBuilder.shareDoc(invoiceDoc(d), b))),
        if (r.planId != null)
          AppButton('View plan', icon: Icons.event_repeat_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () {
            Navigator.pop(context);
            GoRouter.of(context).push('/installments/${r.planId}');
          }),
        AppButton('View', icon: Icons.receipt_long_outlined, kind: ButtonKind.secondary, dense: true, onPressed: () {
          Navigator.pop(context);
          GoRouter.of(context).push('/sales/${r.id}');
        }),
        AppButton('New sale', dense: true, onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}
