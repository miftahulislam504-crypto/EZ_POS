import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/attachments_section.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/security/password_confirm.dart';
import 'collect_installment_sheet.dart';
import 'installment_docs.dart';
import 'installments_data.dart';

class PlanDetailPage extends ConsumerWidget {
  const PlanDetailPage({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(planDetailProvider(planId));
    return PageScaffold(
      title: 'Installment plan',
      maxWidth: 820,
      body: AsyncBody<PlanDetail>(
        value: value,
        onRetry: () => ref.invalidate(planDetailProvider(planId)),
        builder: (d) => _PlanBody(detail: d),
      ),
    );
  }
}

class _PlanBody extends ConsumerWidget {
  const _PlanBody({required this.detail});

  final PlanDetail detail;

  Future<void> _refresh(WidgetRef ref) async {
    refreshAfterTransaction(ref);
    ref.invalidate(planDetailProvider(detail.plan.id));
  }

  Future<void> _collect(BuildContext context, WidgetRef ref, {String? itemId, double? suggested}) async {
    final res = await showCollectInstallment(context, planId: detail.plan.id, itemId: itemId, suggested: suggested);
    if (res != null && context.mounted) {
      showToast(context, 'Received. Receipt ${res['receipt_no']}');
      await _refresh(ref);
    }
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref, InstallmentItem item) async {
    final ok = await showAppSheet<bool>(
      context,
      title: 'Change due date',
      builder: (_) => _RescheduleForm(item: item),
    );
    if (ok == true && context.mounted) {
      showToast(context, 'Due date changed');
      await _refresh(ref);
    }
  }

  Future<void> _addFollowup(BuildContext context, WidgetRef ref) async {
    final ok = await showAppSheet<bool>(context, title: 'Follow-up task', builder: (_) => _FollowupForm(planId: detail.plan.id));
    if (ok == true) await _refresh(ref);
  }

  Future<void> _print(BuildContext context, WidgetRef ref, PrintableDoc doc, {bool share = false}) async {
    final b = ref.read(currentUserProvider).business;
    try {
      share ? await PdfBuilder.shareDoc(doc, b, paper: PaperSize.a4) : await PdfBuilder.printDoc(doc, b, paper: PaperSize.a4);
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final p = detail.plan;
    final today = DateTime.now();
    final progress = p.totalPayable <= 0 ? 0.0 : (p.paid / p.totalPayable).clamp(0.0, 1.0);
    final canCollect = user.can(Perm.installmentsCollect) && p.isActive;
    final canReschedule = user.can(Perm.installmentsReschedule) && p.isActive;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(p.customerName, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.customerName, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text('${p.planNo}  |  ${p.invoiceNo}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                      ],
                    ),
                  ),
                  StatusPill(
                    p.isActive && p.isOverdue ? 'Overdue' : p.status[0].toUpperCase() + p.status.substring(1),
                    tone: p.isActive && p.isOverdue ? Tone.danger : (p.status == 'completed' ? Tone.success : Tone.info),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: c.surfaceMuted, color: c.primary),
              ),
              const SizedBox(height: 12),
              InfoRow('Product total', Fmt.money(p.productTotal)),
              InfoRow('Down payment', Fmt.money(p.downPayment)),
              InfoRow('Financed', Fmt.money(p.financed)),
              if (p.serviceCharge > 0) InfoRow('Service charge', Fmt.money(p.serviceCharge)),
              if (p.returned > 0.004) InfoRow('Goods returned (taken off the plan)', Fmt.money(p.returned), valueColor: c.warning),
              InfoRow('Total payable', Fmt.money(p.totalPayable), bold: true),
              InfoRow('Paid in installments', Fmt.money(p.paid), valueColor: c.success),
              InfoRow('Outstanding', Fmt.money(p.outstanding), bold: true, valueColor: p.outstanding > 0.004 ? c.danger : c.success),
              if (p.overdueAmount > 0.004) InfoRow('Overdue now', '${Fmt.money(p.overdueAmount)} (${p.overdueCount})', valueColor: c.danger, bold: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (canCollect) AppButton('Collect', icon: Icons.payments_outlined, dense: true, onPressed: () => _collect(context, ref)),
            if (canCollect) AppButton('Follow-up', icon: Icons.flag_outlined, kind: ButtonKind.secondary, dense: true, onPressed: () => _addFollowup(context, ref)),
            AppButton('Agreement', icon: Icons.description_outlined, kind: ButtonKind.secondary, dense: true, onPressed: () => _print(context, ref, installmentAgreementDoc(detail))),
            AppButton('Share', icon: Icons.ios_share_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => _print(context, ref, installmentAgreementDoc(detail), share: true)),
            AppButton('Invoice', icon: Icons.receipt_long_outlined, kind: ButtonKind.secondary, dense: true, onPressed: () => context.push('/sales/${p.saleId}')),
            if (user.can(Perm.customersView))
              AppButton('Customer', icon: Icons.person_outline_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => context.push('/customers/${p.customerId}')),
          ],
        ),
        const SizedBox(height: 20),
        const SectionHeader('Schedule'),
        for (final i in detail.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: i.status == 'paid' ? c.successSoft : (i.isOverdueOn(today) ? c.dangerSoft : c.surfaceMuted),
                    child: Text('${i.seq}', style: TextStyle(fontWeight: FontWeight.w800, color: i.status == 'paid' ? c.success : (i.isOverdueOn(today) ? c.danger : c.text))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Fmt.date(i.dueDate), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          i.rescheduled ? 'Originally ${Fmt.date(i.originalDueDate)}' : (i.paid > 0 && i.isOpen ? 'Paid ${Fmt.money(i.paid)}' : ' '),
                          style: context.text.bodySmall?.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MoneyText(i.amount, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      StatusPill(
                        switch (i.status) {
                          'paid' => 'Paid',
                          'partial' => 'Partial',
                          'cancelled' => 'Cancelled',
                          _ => i.isOverdueOn(today) ? 'Overdue' : 'Upcoming',
                        },
                        tone: switch (i.status) {
                          'paid' => Tone.success,
                          'partial' => Tone.warning,
                          'cancelled' => Tone.neutral,
                          _ => i.isOverdueOn(today) ? Tone.danger : Tone.info,
                        },
                      ),
                    ],
                  ),
                  if (i.isOpen && (canCollect || canReschedule))
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'collect') _collect(context, ref, itemId: i.id, suggested: i.remaining);
                        if (v == 'reschedule') _reschedule(context, ref, i);
                      },
                      itemBuilder: (_) => [
                        if (canCollect) const PopupMenuItem(value: 'collect', child: Text('Collect this installment')),
                        if (canReschedule) const PopupMenuItem(value: 'reschedule', child: Text('Change due date')),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (detail.dateChanges.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SectionHeader('Due date changes'),
          for (final ch in detail.dateChanges)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_calendar_outlined),
              title: Text('Installment ${ch.seq}: ${Fmt.date(ch.oldDate)} to ${Fmt.date(ch.newDate)}'),
              subtitle: Text('${ch.reason}  |  ${Fmt.dateTime(ch.at)}'),
            ),
        ],
        const SizedBox(height: 16),
        const SectionHeader('Payments received'),
        if (detail.payments.isEmpty)
          Text('No installment has been collected yet.', style: context.text.bodyMedium?.copyWith(color: c.textMuted))
        else
          for (final pay in detail.payments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const IconBadge(Icons.south_west_rounded, tone: Tone.success, size: 40),
              title: Text(Fmt.money(pay.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${pay.receiptNo}  |  ${pay.accountName}  |  ${Fmt.dateTime(pay.date)}${pay.advance > 0.004 ? '  |  advance ${Fmt.money(pay.advance)}' : ''}'),
              trailing: IconButton(
                tooltip: 'Print receipt',
                icon: const Icon(Icons.print_outlined),
                onPressed: () => _print(context, ref, installmentReceiptDoc(detail, pay)),
              ),
            ),
        if (detail.guarantors.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader('Guarantors and references'),
          for (final g in detail.guarantors)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(g.name, size: 40),
              title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                g.kind == 'guarantor' ? 'Guarantor' : g.kind == 'reference' ? 'Reference' : 'Emergency contact',
                g.relationship,
                g.phone,
                g.address,
              ].whereType<String>().where((s) => s.isNotEmpty).join('  |  ')),
            ),
        ],
        const SizedBox(height: 16),
        AttachmentsSection(
          entityType: 'installment',
          entityId: p.id,
          title: 'Agreements and documents',
          subtitle: 'Signed agreement, guarantor NID copies',
          canEdit: user.can(Perm.installmentsCollect),
          canDelete: user.can(Perm.installmentsManage),
        ),
        const SizedBox(height: 16),
        SectionHeader('Follow-ups', trailing: canCollect ? AppButton('Add', icon: Icons.add_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => _addFollowup(context, ref)) : null),
        if (detail.followups.isEmpty)
          Text('No follow-up tasks.', style: context.text.bodyMedium?.copyWith(color: c.textMuted))
        else
          for (final f in detail.followups)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(f.isOpen ? Icons.radio_button_unchecked_rounded : Icons.check_circle_rounded, color: f.isOpen ? c.warning : c.success),
              title: Text(f.note, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Due ${Fmt.date(f.dueDate)}${f.outcome == null ? '' : '  |  ${f.outcome}'}'),
              trailing: f.isOpen && canCollect
                  ? TextButton(
                      onPressed: () async {
                        final outcome = await reasonDialog(context, title: 'Complete follow-up', message: 'What was the outcome?', confirmLabel: 'Done', danger: false);
                        if (outcome == null) return;
                        try {
                          await ref.read(installmentsRepoProvider).completeFollowup(f.id, outcome);
                          await _refresh(ref);
                        } catch (e) {
                          if (context.mounted) showToast(context, friendlyError(e), error: true);
                        }
                      },
                      child: const Text('Done'),
                    )
                  : null,
            ),
        if (detail.reminders.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader('Reminders sent'),
          for (final r in detail.reminders.take(8))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_none_rounded),
              title: Text('${r.kind[0].toUpperCase()}${r.kind.substring(1)} reminder via ${r.channel}'),
              subtitle: Text(Fmt.dateTime(r.at)),
            ),
        ],
        if (user.can(Perm.installmentsManage) && p.isActive) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.remindersEnabled,
            title: const Text('Reminders for this plan', style: TextStyle(fontWeight: FontWeight.w700)),
            onChanged: (v) async {
              try {
                await ref.read(installmentsRepoProvider).setReminders(p.id, v);
                await _refresh(ref);
              } catch (e) {
                if (context.mounted) showToast(context, friendlyError(e), error: true);
              }
            },
          ),
        ],
      ],
    );
  }
}

class _RescheduleForm extends ConsumerStatefulWidget {
  const _RescheduleForm({required this.item});

  final InstallmentItem item;

  @override
  ConsumerState<_RescheduleForm> createState() => _RescheduleFormState();
}

class _RescheduleFormState extends ConsumerState<_RescheduleForm> {
  late DateTime _date = widget.item.dueDate.add(const Duration(days: 7));
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) return setState(() => _error = 'Write the reason for the change.');
    if (!await confirmSensitive(context, ref, message: 'Changing a due date is recorded with your name. Enter your password to continue.')) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(installmentsRepoProvider).reschedule(widget.item.id, _date, _reason.text.trim());
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Installment ${widget.item.seq}  |  currently due ${Fmt.date(widget.item.dueDate)}', style: context.text.bodyMedium?.copyWith(color: c.textMuted)),
        const SizedBox(height: 14),
        DateField(
          label: 'New due date',
          value: _date,
          firstDate: DateTime.now().subtract(const Duration(days: 30)),
          lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
          onChanged: (d) => setState(() => _date = d ?? _date),
        ),
        const SizedBox(height: 14),
        AppTextField(controller: _reason, label: 'Reason', hint: 'Why is the date changing?', maxLines: 2),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
        const SizedBox(height: 6),
        Text('The old date is kept in the plan history.', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
        const SizedBox(height: 14),
        AppButton('Change date', expand: true, loading: _saving, onPressed: _save),
      ],
    );
  }
}

class _FollowupForm extends ConsumerStatefulWidget {
  const _FollowupForm({required this.planId});

  final String planId;

  @override
  ConsumerState<_FollowupForm> createState() => _FollowupFormState();
}

class _FollowupFormState extends ConsumerState<_FollowupForm> {
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_note.text.trim().isEmpty) return setState(() => _error = 'Write what needs to be done.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(installmentsRepoProvider).addFollowup({'plan_id': widget.planId, 'due_date': Fmt.iso(_date), 'note': _note.text.trim()});
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(controller: _note, label: 'Task or next reminder', hint: 'Call customer, visit shop...', maxLines: 2, autofocus: true),
        const SizedBox(height: 14),
        DateField(
          label: 'Follow up on',
          value: _date,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          onChanged: (d) => setState(() => _date = d ?? _date),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: context.colors.danger, fontWeight: FontWeight.w700))),
        const SizedBox(height: 16),
        AppButton('Save follow-up', expand: true, loading: _saving, onPressed: _save),
      ],
    );
  }
}
