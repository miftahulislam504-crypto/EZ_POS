import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/common_data.dart';
import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../suppliers/suppliers_data.dart';
import 'customers_data.dart';

enum PartyKind { customer, supplier }

/// "Due 1,200.00" / "Advance 300.00" / "Settled" label.
class BalanceLabel extends StatelessWidget {
  const BalanceLabel(this.balance, {super.key, this.kind = PartyKind.customer, this.large = false});

  final double balance;
  final PartyKind kind;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final owed = balance > 0.004;
    final advance = balance < -0.004;
    final label = owed
        ? (kind == PartyKind.customer ? 'Due' : 'Payable')
        : advance
            ? 'Advance'
            : 'Settled';
    final color = owed ? c.danger : (advance ? c.success : c.textMuted);
    final size = large ? context.text.headlineSmall : context.text.titleSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
        if (owed || advance) MoneyText(balance.abs(), style: size?.copyWith(fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}

/// Chronological ledger, newest first, with a running balance.
class LedgerList extends StatelessWidget {
  const LedgerList({super.key, required this.entries, required this.kind});

  final List<LedgerEntry> entries;
  final PartyKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (entries.isEmpty) {
      return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions yet', message: 'Sales, payments and returns will appear here.');
    }
    final receivable = kind == PartyKind.customer;
    final rows = entries.reversed.toList();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = rows[i];
        final charge = receivable ? e.debit : e.credit;
        final paid = receivable ? e.credit : e.debit;
        final isCharge = charge > 0;
        final amount = isCharge ? charge : paid;
        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              IconBadge(isCharge ? Icons.north_east_rounded : Icons.south_west_rounded, tone: isCharge ? Tone.danger : Tone.success, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.description.isEmpty ? e.type : e.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(Fmt.dateTime(e.date), style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(amount,
                      style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: isCharge ? c.danger : c.success)),
                  const SizedBox(height: 2),
                  Text('Balance ${Fmt.money(e.balance)}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Aging of open invoices: 0-30, 31-60, 61-90, 90+ days.
class AgingStrip extends StatelessWidget {
  const AgingStrip(this.items, {super.key});

  final List<OpenItem> items;

  @override
  Widget build(BuildContext context) {
    double sum(bool Function(int) test) => items.where((i) => test(i.ageDays)).fold(0.0, (s, i) => s + i.due);
    final buckets = [
      ('0-30 days', sum((d) => d <= 30), Tone.success),
      ('31-60 days', sum((d) => d > 30 && d <= 60), Tone.info),
      ('61-90 days', sum((d) => d > 60 && d <= 90), Tone.warning),
      ('90+ days', sum((d) => d > 90), Tone.danger),
    ];
    return Row(
      children: [
        for (final b in buckets)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: b.$3.bg(context), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.$1, style: TextStyle(fontSize: 11, color: b.$3.fg(context), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(Fmt.money(b.$2), style: TextStyle(fontWeight: FontWeight.w800, color: b.$3.fg(context)))),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Receive a customer payment or make a supplier payment.
Future<bool> showPartyPaymentSheet(
  BuildContext context,
  WidgetRef ref, {
  required PartyKind kind,
  required String partyId,
  required String partyName,
  required double balance,
  required List<OpenItem> openItems,
  String? partyPhone,
  String? preselectId,
}) async {
  final result = await showAppSheet<_PaymentResult>(
    context,
    title: kind == PartyKind.customer ? 'Receive payment' : 'Make payment',
    builder: (_) => _PaymentForm(kind: kind, partyId: partyId, partyName: partyName, balance: balance, openItems: openItems, preselectId: preselectId),
  );
  if (result == null) return false;
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ReceiptDialog(kind: kind, partyName: partyName, partyPhone: partyPhone, balanceBefore: balance, result: result),
    );
  }
  return true;
}

class _PaymentResult {
  const _PaymentResult({required this.number, required this.amount, required this.method, required this.date});

  final String number;
  final double amount;
  final String method;
  final DateTime date;
}

class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm({required this.kind, required this.partyId, required this.partyName, required this.balance, required this.openItems, this.preselectId});

  final PartyKind kind;
  final String partyId;
  final String partyName;
  final double balance;
  final List<OpenItem> openItems;
  final String? preselectId;

  @override
  ConsumerState<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<_PaymentForm> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.balance > 0.004 ? widget.balance.toStringAsFixed(2) : '');
  final _reference = TextEditingController();
  final _note = TextEditingController();
  final String _clientRef = const Uuid().v4();
  String? _accountId;
  late bool _manual = widget.preselectId != null;
  late final Set<String> _selected = {if (widget.preselectId != null) widget.preselectId!};
  bool _saving = false;
  String? _error;

  bool get _isCustomer => widget.kind == PartyKind.customer;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _allocations(double amount) {
    var remaining = amount;
    final out = <Map<String, dynamic>>[];
    for (final item in widget.openItems) {
      if (!_selected.contains(item.id) || remaining <= 0) continue;
      final take = remaining < item.due ? remaining : item.due;
      out.add({_isCustomer ? 'sale_id' : 'purchase_id': item.id, 'amount': take});
      remaining -= take;
    }
    return out;
  }

  Future<void> _submit(List<PaymentAccount> accounts) async {
    final amount = Fmt.parse(_amount.text);
    if (amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Choose a payment method');
      return;
    }
    if (_manual && _selected.isEmpty) {
      setState(() => _error = 'Select at least one invoice, or switch to automatic');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final payload = <String, dynamic>{
        _isCustomer ? 'customer_id' : 'supplier_id': widget.partyId,
        'amount': amount,
        'account_id': _accountId,
        'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'client_ref': _clientRef,
        if (_manual) 'allocations': _allocations(amount),
      };
      final res = _isCustomer
          ? await ref.read(customerRepoProvider).receivePayment(payload)
          : await ref.read(supplierRepoProvider).makePayment(payload);
      refreshAfterTransaction(ref);
      final method = accounts.firstWhere((a) => a.id == _accountId).name;
      if (mounted) {
        Navigator.pop(
          context,
          _PaymentResult(
            number: (res[_isCustomer ? 'receipt_no' : 'payment_no'] ?? '') as String,
            amount: amount,
            method: method,
            date: DateTime.now(),
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
    final accounts = (ref.watch(paymentAccountsProvider).valueOrNull ?? const <PaymentAccount>[]).where((a) => a.isActive).toList();
    if (_accountId == null && accounts.isNotEmpty) _accountId = accounts.first.id;
    final selectedAccount = accounts.where((a) => a.id == _accountId).firstOrNull;
    final amount = Fmt.parse(_amount.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          color: c.surfaceMuted,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Avatar(widget.partyName, size: 40),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.partyName, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              BalanceLabel(widget.balance, kind: widget.kind),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MoneyField(controller: _amount, label: 'Amount', autofocus: true, onChanged: (_) => setState(() {})),
        if (widget.balance > 0.004)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, children: [
              ActionChip(label: const Text('Full amount'), onPressed: () => setState(() => _amount.text = widget.balance.toStringAsFixed(2))),
              if (widget.balance > 1)
                ActionChip(label: const Text('Half'), onPressed: () => setState(() => _amount.text = (widget.balance / 2).toStringAsFixed(2))),
            ]),
          ),
        const SizedBox(height: 16),
        Text('Payment method', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: c.textMuted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in accounts)
              ChoiceChip(label: Text(a.name), selected: _accountId == a.id, onSelected: (_) => setState(() => _accountId = a.id)),
          ],
        ),
        if (selectedAccount != null && !selectedAccount.isCash) ...[
          const SizedBox(height: 14),
          AppTextField(controller: _reference, label: 'Transaction reference', hint: 'Transaction ID or last digits'),
        ],
        if (widget.openItems.isNotEmpty) ...[
          const SizedBox(height: 18),
          SegmentedButton<bool>(
            segments: [
              const ButtonSegment(value: false, label: Text('Oldest first')),
              ButtonSegment(value: true, label: Text(_isCustomer ? 'Choose invoices' : 'Choose bills')),
            ],
            selected: {_manual},
            onSelectionChanged: (s) => setState(() => _manual = s.first),
          ),
          if (_manual)
            for (final item in widget.openItems)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _selected.contains(item.id),
                onChanged: (v) => setState(() => v == true ? _selected.add(item.id) : _selected.remove(item.id)),
                title: Text(item.number, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${Fmt.date(item.date)}  |  ${item.ageDays} days'),
                secondary: Text(Fmt.money(item.due), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          if (!_manual)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _isCustomer
                    ? 'The amount settles the oldest unpaid invoices first. Any extra is kept as customer advance.'
                    : 'The amount settles the oldest unpaid bills first. Any extra is kept as advance paid.',
                style: context.text.bodySmall?.copyWith(color: c.textMuted),
              ),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              _isCustomer ? 'No unpaid invoices. This will be kept as customer advance.' : 'No unpaid bills. This will be kept as advance paid.',
              style: context.text.bodySmall?.copyWith(color: c.textMuted),
            ),
          ),
        const SizedBox(height: 14),
        AppTextField(controller: _note, label: 'Note (optional)'),
        if (amount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: InfoRow('Balance after payment', Fmt.money(widget.balance - amount), bold: true),
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w600))),
        const SizedBox(height: 18),
        AppButton(_isCustomer ? 'Receive payment' : 'Make payment', expand: true, loading: _saving, onPressed: () => _submit(accounts)),
      ],
    );
  }
}

class _ReceiptDialog extends ConsumerWidget {
  const _ReceiptDialog({required this.kind, required this.partyName, required this.partyPhone, required this.balanceBefore, required this.result});

  final PartyKind kind;
  final String partyName;
  final String? partyPhone;
  final double balanceBefore;
  final _PaymentResult result;

  PrintableDoc _doc() {
    final customer = kind == PartyKind.customer;
    return PrintableDoc(
      title: customer ? 'Payment receipt' : 'Payment voucher',
      number: result.number,
      date: result.date,
      partyLabel: customer ? 'Customer' : 'Supplier',
      partyName: partyName,
      partyPhone: partyPhone,
      totals: [
        (customer ? 'Amount received' : 'Amount paid', Fmt.pdfMoney(result.amount), true),
        ('Previous balance', Fmt.pdfMoney(balanceBefore), false),
        ('Balance after', Fmt.pdfMoney(balanceBefore - result.amount), false),
      ],
      payments: [(result.method, Fmt.pdfMoney(result.amount))],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final business = ref.watch(currentUserProvider).business;
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          const IconBadge(Icons.check_rounded, tone: Tone.success, size: 64),
          const SizedBox(height: 16),
          Text(kind == PartyKind.customer ? 'Payment received' : 'Payment made', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          MoneyText(result.amount, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: c.success)),
          const SizedBox(height: 4),
          Text('${result.number}  |  ${result.method}', style: TextStyle(color: c.textMuted)),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowAlignment: OverflowBarAlignment.center,
      actions: [
        AppButton('Print', icon: Icons.print_outlined, kind: ButtonKind.secondary, dense: true, onPressed: () => PdfBuilder.printDoc(_doc(), business)),
        AppButton('Share', icon: Icons.ios_share_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => PdfBuilder.shareDoc(_doc(), business)),
        AppButton('Done', dense: true, onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}
