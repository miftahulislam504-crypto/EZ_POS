import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/security/password_confirm.dart';
import 'cash_data.dart';
import 'cash_widgets.dart';

PrintableDoc dayClosingDoc(Map<String, dynamic> s, {String? branch, String? closedBy, DateTime? closedAt}) {
  PrintLine row(String name, num v) => PrintLine(name: name, qty: '', price: 0, total: v.toDouble());
  final sales = asMap(s['sales']);
  return PrintableDoc(
    title: 'Day closing report',
    number: s['date']?.toString() ?? '',
    date: closedAt ?? DateTime.now(),
    partyLabel: 'Branch',
    partyName: branch ?? '',
    meta: [if (closedBy != null) ('Closed by', closedBy)],
    simple: true,
    lines: [
      row('Invoices (${intOf(sales['count'])})', dbl(sales['total'])),
      row('Item and invoice discounts', dbl(sales['discount'])),
      row('Credit given on sales', dbl(s['credit_sales'])),
      row('Sales returns', dbl(s['sales_returns'])),
      for (final c in asRows(s['collections'])) row('Collected: ${c['account']}', dbl(c['amount'])),
      row('Customer dues collected', dbl(s['customer_collected'])),
      row('Installments collected', dbl(s['installment_collected'])),
      row('Expenses', dbl(s['expenses'])),
      row('Supplier payments', dbl(s['supplier_paid'])),
      row('Refunds paid', dbl(s['refunds'])),
      for (final b in asRows(s['other_balances'])) row('Balance: ${b['account']}', dbl(b['balance'])),
    ],
    totals: [
      ('Opening cash', Fmt.pdfMoney(dbl(s['opening_cash'])), false),
      ('Cash in', Fmt.pdfMoney(dbl(s['cash_in'])), false),
      ('Cash out', Fmt.pdfMoney(dbl(s['cash_out'])), false),
      ('Expected cash', Fmt.pdfMoney(dbl(s['expected_cash'])), true),
      if (s['counted_cash'] != null) ('Counted cash', Fmt.pdfMoney(dbl(s['counted_cash'])), true),
      if (s['difference'] != null) ('Difference', Fmt.pdfMoney(dbl(s['difference'])), false),
    ],
    qrData: s['date']?.toString(),
  );
}

class DayClosingPage extends ConsumerStatefulWidget {
  const DayClosingPage({super.key});

  @override
  ConsumerState<DayClosingPage> createState() => _DayClosingPageState();
}

class _DayClosingPageState extends ConsumerState<DayClosingPage> {
  DateTime _date = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final _counted = TextEditingController();
  final _reason = TextEditingController();
  final _note = TextEditingController();
  Map<String, int>? _notes;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _counted.dispose();
    _reason.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _count(double expected) async {
    final r = await showCashCount(context, expected: expected);
    if (r != null) {
      setState(() {
        _counted.text = r.total.toStringAsFixed(2);
        _notes = r.notes;
      });
    }
  }

  Future<void> _close() async {
    if (_counted.text.trim().isEmpty) return setState(() => _error = 'Enter the counted cash.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(cashRepoProvider).closeDay({
        'closing_date': Fmt.iso(_date),
        'counted_cash': Fmt.parse(_counted.text),
        'difference_reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        'denominations': _notes,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      refreshAfterTransaction(ref);
      ref.invalidate(dayPreviewProvider(_date));
      ref.invalidate(dayClosingsProvider);
      if (mounted) {
        setState(() {
          _saving = false;
          _counted.clear();
          _reason.clear();
        });
        showToast(context, 'Day closed');
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

  Future<void> _reopen(String id) async {
    final reason = await reasonDialog(context, title: 'Reopen this day', message: 'The cash difference posted at closing is reversed. You can close the day again afterwards.', confirmLabel: 'Reopen');
    if (reason == null || !mounted) return;
    if (!await confirmSensitive(context, ref)) return;
    try {
      await ref.read(cashRepoProvider).reopenDay(id, reason);
      refreshAfterTransaction(ref);
      ref.invalidate(dayPreviewProvider(_date));
      ref.invalidate(dayClosingsProvider);
      if (mounted) showToast(context, 'Day reopened');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    if (!user.can(Perm.cashView)) {
      return const PageScaffold(title: 'Day closing', body: EmptyState(icon: Icons.lock_outline_rounded, title: 'No access', message: 'Your role does not include day closing.'));
    }
    final preview = ref.watch(dayPreviewProvider(_date));
    final history = ref.watch(dayClosingsProvider);
    return PageScaffold(
      title: 'Day closing',
      maxWidth: 820,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          DateField(
            label: 'Business day',
            value: _date,
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now(),
            onChanged: (d) => setState(() => _date = d ?? _date),
          ),
          const SizedBox(height: 14),
          AsyncBody<Map<String, dynamic>>(
            value: preview,
            onRetry: () => ref.invalidate(dayPreviewProvider(_date)),
            builder: (p) {
              final closed = p['closed'] == true;
              final expected = dbl(p['expected_cash']);
              final openShifts = intOf(p['open_shifts']);
              final sales = asMap(p['sales']);
              final diff = Fmt.parse(_counted.text) - expected;
              final canClose = user.can(Perm.cashCloseDay) && !closed;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (closed)
                    AppCard(
                      color: c.successSoft,
                      borderColor: Colors.transparent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('This day is closed', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: c.success)),
                          const SizedBox(height: 4),
                          Text('Final cash counted ${Fmt.money(dbl(p['closed_counted_cash']))}  |  difference ${Fmt.money(dbl(p['closed_difference']))}'),
                          if (user.can(Perm.cashReopen) && p['closing_id'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: AppButton('Reopen day', icon: Icons.lock_open_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => _reopen(p['closing_id'] as String)),
                            ),
                        ],
                      ),
                    )
                  else if (openShifts > 0)
                    AppCard(
                      color: c.warningSoft,
                      borderColor: Colors.transparent,
                      child: Text('$openShifts cashier shift(s) are still open. Close them before closing the day. The cash figure below is not final.', style: TextStyle(color: c.warning, fontWeight: FontWeight.w700)),
                    ),
                  const SizedBox(height: 14),
                  AppCard(
                    child: Column(
                      children: [
                        InfoRow('Invoices', '${intOf(sales['count'])}  |  ${Fmt.money(dbl(sales['total']))}'),
                        InfoRow('Credit given on sales', Fmt.money(dbl(p['credit_sales']))),
                        InfoRow('Sales returns', Fmt.money(dbl(p['sales_returns']))),
                        for (final x in asRows(p['collections'])) InfoRow('Collected: ${x['account']}', Fmt.money(dbl(x['amount'])), valueColor: c.success),
                        InfoRow('Customer dues collected', Fmt.money(dbl(p['customer_collected']))),
                        InfoRow('Installments collected', Fmt.money(dbl(p['installment_collected']))),
                        InfoRow('Expenses', Fmt.money(dbl(p['expenses'])), valueColor: c.danger),
                        InfoRow('Supplier payments', Fmt.money(dbl(p['supplier_paid'])), valueColor: c.danger),
                        InfoRow('Refunds paid', Fmt.money(dbl(p['refunds'])), valueColor: c.danger),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppCard(
                    child: Column(
                      children: [
                        InfoRow('Opening cash', Fmt.money(dbl(p['opening_cash']))),
                        InfoRow('Cash in', Fmt.money(dbl(p['cash_in'])), valueColor: c.success),
                        InfoRow('Cash out', Fmt.money(dbl(p['cash_out'])), valueColor: c.danger),
                        const Divider(height: 18),
                        InfoRow(closed ? 'Cash expected at closing' : 'Cash expected (not final)', Fmt.money(expected), bold: true),
                        for (final b in asRows(p['other_balances'])) InfoRow('${b['account']} balance', Fmt.money(dbl(b['balance']))),
                      ],
                    ),
                  ),
                  if (canClose) ...[
                    const SizedBox(height: 14),
                    MoneyField(controller: _counted, label: 'Counted cash', onChanged: (_) => setState(() {})),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: AppButton('Count notes and coins', icon: Icons.calculate_outlined, kind: ButtonKind.secondary, dense: true, onPressed: () => _count(expected))),
                    if (_counted.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(diff.abs() < 0.005 ? 'The drawer matches the system.' : '${diff > 0 ? 'Over' : 'Short'} by ${Fmt.money(diff.abs())}', style: TextStyle(color: diff.abs() < 0.005 ? c.success : c.warning, fontWeight: FontWeight.w800)),
                      if (diff.abs() >= 0.005) ...[const SizedBox(height: 10), AppTextField(controller: _reason, label: 'Reason for the difference', maxLines: 2)],
                    ],
                    const SizedBox(height: 12),
                    AppTextField(controller: _note, label: 'Note (optional)'),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
                    const SizedBox(height: 14),
                    AppButton('Close the day', icon: Icons.event_available_rounded, loading: _saving, onPressed: openShifts > 0 ? null : _close),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton('Print report', icon: Icons.print_outlined, kind: ButtonKind.secondary, dense: true, onPressed: () async {
                      try {
                        await PdfBuilder.printDoc(dayClosingDoc(p, branch: p['branch_name'] as String?), user.business, paper: PaperSize.a4);
                      } catch (e) {
                        if (context.mounted) showToast(context, friendlyError(e), error: true);
                      }
                    }),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          const SectionHeader('Closed days'),
          history.when(
            loading: () => const ListSkeleton(rows: 3),
            error: (e, _) => Text(friendlyError(e), style: TextStyle(color: c.danger)),
            data: (rows) => rows.isEmpty
                ? Text('No day has been closed yet.', style: context.text.bodyMedium?.copyWith(color: c.textMuted))
                : Column(
                    children: [
                      for (final r in rows)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: IconBadge(r.isClosed ? Icons.check_circle_outline_rounded : Icons.history_rounded, tone: r.isClosed ? Tone.success : Tone.neutral, size: 40),
                          title: Text(Fmt.date(r.date), style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${r.closedByName ?? ''}  |  counted ${Fmt.money(r.counted)}${r.isClosed ? '' : '  |  reopened: ${r.reopenReason ?? ''}'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (r.difference.abs() > 0.004) Text('${r.difference > 0 ? '+' : ''}${Fmt.money(r.difference)}', style: TextStyle(color: r.difference > 0 ? c.success : c.danger, fontWeight: FontWeight.w800)),
                              IconButton(
                                tooltip: 'Print',
                                icon: const Icon(Icons.print_outlined),
                                onPressed: () => PdfBuilder.printDoc(dayClosingDoc(r.summary, closedBy: r.closedByName, closedAt: r.closedAt), user.business, paper: PaperSize.a4),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
