import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'installments_data.dart';

/// Today's installment reminders. Messages are sent by opening WhatsApp or the SMS app with the text filled in;
/// each send is logged so the same customer is not reminded twice in a day.
class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(installmentRemindersProvider);
    final followups = ref.watch(openFollowupsProvider);
    final c = context.colors;
    return PageScaffold(
      title: 'Reminders',
      subtitle: 'Due, upcoming and overdue installments',
      maxWidth: 820,
      actions: [
        IconButton(
          tooltip: 'Reminder settings',
          icon: const Icon(Icons.tune_rounded),
          onPressed: ref.watch(currentUserProvider).can(Perm.settingsManage) ? () => context.push('/settings/installments') : null,
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(installmentRemindersProvider);
          ref.invalidate(openFollowupsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            const SectionHeader('To remind today'),
            AsyncBody<List<ReminderRow>>(
              value: reminders,
              onRetry: () => ref.invalidate(installmentRemindersProvider),
              loading: const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              builder: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: 'No reminders to send',
                    message: 'Customers already reminded today, or with reminders turned off, are not listed.',
                  );
                }
                return Column(children: [for (final r in rows) _ReminderCard(row: r)]);
              },
            ),
            const SizedBox(height: 20),
            const SectionHeader('Follow-up tasks'),
            followups.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text(friendlyError(e), style: TextStyle(color: c.danger)),
              data: (items) => items.isEmpty
                  ? Text('No open follow-ups.', style: context.text.bodyMedium?.copyWith(color: c.textMuted))
                  : Column(
                      children: [
                        for (final f in items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: () => context.push('/installments/${f.planId}'),
                            leading: Icon(Icons.flag_outlined, color: f.dueDate.isBefore(DateTime.now()) ? c.danger : c.warning),
                            title: Text(f.note, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${f.customerName ?? ''}  |  ${f.planNo ?? ''}  |  due ${Fmt.date(f.dueDate)}'),
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

String _waNumber(String phone) {
  final d = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('880')) return d;
  if (d.startsWith('01') && d.length == 11) return '880${d.substring(1)}';
  return d;
}

class _ReminderCard extends ConsumerStatefulWidget {
  const _ReminderCard({required this.row});

  final ReminderRow row;

  @override
  ConsumerState<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends ConsumerState<_ReminderCard> {
  bool _busy = false;

  Future<void> _send(String channel) async {
    final r = widget.row;
    final phone = r.phone;
    if (channel != 'call' && (phone == null || phone.trim().isEmpty)) {
      showToast(context, 'This customer has no phone number.', error: true);
      return;
    }
    final Uri uri = switch (channel) {
      'whatsapp' => Uri.parse('https://wa.me/${_waNumber(phone!)}?text=${Uri.encodeComponent(r.message)}'),
      'sms' => Uri(scheme: 'sms', path: phone, queryParameters: {'body': r.message}),
      _ => Uri(scheme: 'tel', path: phone),
    };
    setState(() => _busy = true);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('Could not open the app for $channel.');
      await ref.read(installmentsRepoProvider).logReminder({'item_id': r.itemId, 'kind': r.kind, 'channel': channel, 'message': r.message});
      ref.invalidate(installmentRemindersProvider);
      ref.invalidate(planDetailProvider(r.planId));
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.row;
    final (label, tone) = switch (r.kind) {
      'overdue' => ('Overdue ${r.daysOverdue} day(s)', Tone.danger),
      'due' => ('Due today', Tone.warning),
      _ => ('Due ${Fmt.date(r.dueDate)}', Tone.info),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(r.customerName, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => context.push('/installments/${r.planId}'),
                        child: Text(r.customerName, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      Text('${r.planNo}  |  ${r.phone ?? 'no phone'}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(r.amount, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    StatusPill(label, tone: tone, dense: true),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(10)),
              child: Text(r.message, style: context.text.bodySmall),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton('WhatsApp', icon: Icons.chat_outlined, dense: true, loading: _busy, onPressed: () => _send('whatsapp')),
                AppButton('SMS', icon: Icons.sms_outlined, kind: ButtonKind.secondary, dense: true, onPressed: _busy ? null : () => _send('sms')),
                AppButton('Call', icon: Icons.call_outlined, kind: ButtonKind.secondary, dense: true, onPressed: _busy ? null : () => _send('call')),
                AppButton('Copy', icon: Icons.copy_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: r.message));
                  if (context.mounted) showToast(context, 'Message copied');
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
