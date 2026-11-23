import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'cash_data.dart';
import 'cash_widgets.dart';

/// Cash register: open a shift, record cash in and out, count and close the shift.
class CashPage extends ConsumerWidget {
  const CashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!user.can(Perm.cashView)) {
      return const PageScaffold(title: 'Cash register', body: EmptyState(icon: Icons.lock_outline_rounded, title: 'No access', message: 'Your role does not include the cash register.'));
    }
    final shift = ref.watch(myShiftProvider);
    final history = ref.watch(shiftsProvider);
    final c = context.colors;
    return PageScaffold(
      title: 'Cash register',
      maxWidth: 820,
      actions: [
        if (user.can(Perm.cashCloseDay)) IconButton(tooltip: 'Day closing', icon: const Icon(Icons.event_available_outlined), onPressed: () => context.push('/cash/day-closing')),
        if (user.can(Perm.accountsView)) IconButton(tooltip: 'Accounts', icon: const Icon(Icons.account_balance_outlined), onPressed: () => context.push('/cash/accounts')),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myShiftProvider);
          ref.invalidate(shiftsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            AsyncBody<ShiftRow?>(
              value: shift,
              onRetry: () => ref.invalidate(myShiftProvider),
              builder: (s) => s == null ? const _OpenShiftCard() : _ShiftCard(shift: s),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Recent shifts'),
            history.when(
              loading: () => const ListSkeleton(rows: 3),
              error: (e, _) => Text(friendlyError(e), style: TextStyle(color: c.danger)),
              data: (rows) => rows.isEmpty
                  ? Text('No shifts yet.', style: context.text.bodyMedium?.copyWith(color: c.textMuted))
                  : Column(
                      children: [
                        for (final r in rows)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: IconBadge(r.isOpen ? Icons.lock_open_rounded : Icons.lock_outline_rounded, tone: r.isOpen ? Tone.success : Tone.neutral, size: 40),
                            title: Text('${r.shiftNo}  |  ${r.registerName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${r.openedByName ?? ''}  |  ${Fmt.dateTime(r.openedAt)}${r.closedAt == null ? '' : ' to ${Fmt.dateTime(r.closedAt)}'}'),
                            trailing: r.isOpen
                                ? const StatusPill('Open', tone: Tone.success)
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(Fmt.money(r.counted ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
                                      if ((r.difference ?? 0).abs() > 0.004)
                                        Text('${(r.difference ?? 0) > 0 ? '+' : ''}${Fmt.money(r.difference)}', style: TextStyle(color: (r.difference ?? 0) > 0 ? c.success : c.danger, fontSize: 12, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenShiftCard extends ConsumerStatefulWidget {
  const _OpenShiftCard();

  @override
  ConsumerState<_OpenShiftCard> createState() => _OpenShiftCardState();
}

class _OpenShiftCardState extends ConsumerState<_OpenShiftCard> {
  final _opening = TextEditingController();
  final _note = TextEditingController();
  String? _register;
  bool _saving = false;

  @override
  void dispose() {
    _opening.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() => _saving = true);
    try {
      await ref.read(cashRepoProvider).openShift({'register_id': _register, 'opening_cash': Fmt.parse(_opening.text), 'note': _note.text.trim().isEmpty ? null : _note.text.trim()});
      ref.invalidate(myShiftProvider);
      ref.invalidate(shiftsProvider);
      if (mounted) showToast(context, 'Shift opened');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final registers = (ref.watch(registersProvider).valueOrNull ?? const <RegisterRow>[]).where((r) => r.isActive).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(Icons.lock_open_rounded, tone: Tone.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No open shift', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Count the cash in the drawer and open your shift to start the day.', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          if (user.can(Perm.cashShift)) ...[
            const SizedBox(height: 16),
            if (registers.length > 1)
              PickerField<String>(label: 'Counter', value: _register, options: [for (final r in registers) PickerOption(r.id, r.name)], onChanged: (v) => setState(() => _register = v)),
            if (registers.length > 1) const SizedBox(height: 12),
            MoneyField(controller: _opening, label: 'Opening cash in drawer'),
            const SizedBox(height: 12),
            AppTextField(controller: _note, label: 'Note (optional)'),
            const SizedBox(height: 14),
            AppButton('Open shift', icon: Icons.play_arrow_rounded, loading: _saving, onPressed: _open),
          ],
        ],
      ),
    );
  }
}

class _ShiftCard extends ConsumerWidget {
  const _ShiftCard({required this.shift});

  final ShiftRow shift;

  Future<void> _entry(BuildContext context, WidgetRef ref, String type) async {
    final accounts = await ref.read(accountBalancesProvider.future);
    if (!context.mounted) return;
    final ok = await showAccountEntrySheet(context, entryType: type, accounts: accounts, cashOnly: true);
    if (ok == true) {
      ref.invalidate(shiftSummaryProvider(shift.id));
      if (context.mounted) showToast(context, 'Saved');
    }
  }

  Future<void> _close(BuildContext context, WidgetRef ref, CashSummary summary) async {
    final done = await showAppSheet<bool>(context, title: 'Close shift', maxWidth: 520, builder: (_) => _CloseShift(shift: shift, summary: summary));
    if (done == true) {
      ref.invalidate(myShiftProvider);
      ref.invalidate(shiftsProvider);
      if (context.mounted) showToast(context, 'Shift closed');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final summary = ref.watch(shiftSummaryProvider(shift.id));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(Icons.point_of_sale_rounded, tone: Tone.success),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${shift.shiftNo}  |  ${shift.registerName}', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Opened ${Fmt.dateTime(shift.openedAt)}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                  ],
                ),
              ),
              const StatusPill('Open', tone: Tone.success),
            ],
          ),
          const SizedBox(height: 14),
          summary.when(
            loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text(friendlyError(e), style: TextStyle(color: c.danger)),
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoRow('Opening cash', Fmt.money(s.opening)),
                for (final x in s.bySource)
                  InfoRow('${x.direction == 'in' ? '+' : '-'} ${sourceLabels[x.source] ?? x.source}', Fmt.money(x.amount), valueColor: x.direction == 'in' ? c.success : c.danger),
                const Divider(height: 20),
                InfoRow('Cash expected in drawer', Fmt.money(s.expected), bold: true),
                InfoRow('Sales in this shift', '${s.salesCount}  |  ${Fmt.money(s.salesTotal)}'),
                for (final n in s.nonCash) InfoRow(n.account, '+${Fmt.money(n.inAmt)}  -${Fmt.money(n.outAmt)}'),
                const SizedBox(height: 14),
                if (user.can(Perm.cashShift))
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppButton('Cash in', icon: Icons.add_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => _entry(context, ref, 'deposit')),
                      AppButton('Cash out', icon: Icons.remove_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => _entry(context, ref, 'withdrawal')),
                      AppButton('Close shift', icon: Icons.lock_outline_rounded, dense: true, onPressed: () => _close(context, ref, s)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseShift extends ConsumerStatefulWidget {
  const _CloseShift({required this.shift, required this.summary});

  final ShiftRow shift;
  final CashSummary summary;

  @override
  ConsumerState<_CloseShift> createState() => _CloseShiftState();
}

class _CloseShiftState extends ConsumerState<_CloseShift> {
  final _counted = TextEditingController();
  final _reason = TextEditingController();
  Map<String, int>? _notes;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _counted.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _count() async {
    final r = await showCashCount(context, expected: widget.summary.expected);
    if (r != null) {
      setState(() {
        _counted.text = r.total.toStringAsFixed(2);
        _notes = r.notes;
      });
    }
  }

  Future<void> _save() async {
    if (_counted.text.trim().isEmpty) return setState(() => _error = 'Enter the counted cash.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(cashRepoProvider).closeShift({
        'shift_id': widget.shift.id,
        'counted_cash': Fmt.parse(_counted.text),
        'difference_reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        'denominations': _notes,
      });
      refreshAfterTransaction(ref);
      if (mounted) Navigator.pop(context, true);
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
    final diff = Fmt.parse(_counted.text) - widget.summary.expected;
    final hasCount = _counted.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoRow('Expected in drawer', Fmt.money(widget.summary.expected), bold: true),
        const SizedBox(height: 10),
        MoneyField(controller: _counted, label: 'Counted cash', onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: AppButton('Count notes and coins', icon: Icons.calculate_outlined, kind: ButtonKind.secondary, dense: true, onPressed: _count)),
        if (hasCount) ...[
          const SizedBox(height: 10),
          Text(
            diff.abs() < 0.005 ? 'The drawer matches the system.' : '${diff > 0 ? 'Over' : 'Short'} by ${Fmt.money(diff.abs())}',
            style: TextStyle(color: diff.abs() < 0.005 ? c.success : c.warning, fontWeight: FontWeight.w800),
          ),
          if (diff.abs() >= 0.005) ...[const SizedBox(height: 10), AppTextField(controller: _reason, label: 'Reason for the difference', maxLines: 2)],
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
        const SizedBox(height: 16),
        AppButton('Close shift', expand: true, loading: _saving, onPressed: _save),
      ],
    );
  }
}
