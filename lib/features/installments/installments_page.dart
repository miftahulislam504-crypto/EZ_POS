import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/surfaces.dart';
import 'collect_installment_sheet.dart';
import 'installments_data.dart';
import 'plan_card.dart';

class InstallmentsPage extends ConsumerWidget {
  const InstallmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!user.can(Perm.installmentsView)) {
      return const PageScaffold(
        title: 'Installments',
        body: EmptyState(icon: Icons.lock_outline_rounded, title: 'No access', message: 'Your role does not include installments.'),
      );
    }
    const tabs = ['Today', 'Next 7 days', '15 days', '30 days', 'Overdue', 'All plans'];
    return DefaultTabController(
      length: tabs.length,
      initialIndex: 0,
      child: PageScaffold(
        title: 'Installments',
        actions: [
          IconButton(tooltip: 'Reminders', icon: const Icon(Icons.notifications_active_outlined), onPressed: () => context.push('/installments/reminders')),
          if (user.can(Perm.reportsView) || user.can(Perm.installmentsView))
            IconButton(tooltip: 'Report', icon: const Icon(Icons.bar_chart_rounded), onPressed: () => context.push('/installments/report')),
        ],
        bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t)]),
        body: const TabBarView(
          children: [
            _DueList(scope: DueScope.today),
            _DueList(scope: DueScope.week),
            _DueList(scope: DueScope.fortnight),
            _DueList(scope: DueScope.month),
            _DueList(scope: DueScope.overdue),
            _PlansList(),
          ],
        ),
      ),
    );
  }
}

class _SummaryStrip extends ConsumerWidget {
  const _SummaryStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(installmentSummaryProvider).valueOrNull;
    if (s == null) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 168,
            child: StatCard(label: 'Due today', value: s.dueTodayAmount, icon: Icons.today_rounded, tone: Tone.info, caption: '${s.dueTodayCount} installments'),
          ),
          SizedBox(
            width: 168,
            child: StatCard(label: 'Overdue', value: s.overdueAmount, icon: Icons.warning_amber_rounded, tone: Tone.danger, caption: '${s.overdueCount} installments'),
          ),
          SizedBox(
            width: 168,
            child: StatCard(label: 'Collected today', value: s.collectedToday, icon: Icons.payments_outlined, tone: Tone.success, caption: 'This month ${Fmt.money(s.collectedMonth)}'),
          ),
          SizedBox(
            width: 168,
            child: StatCard(label: 'Outstanding', value: s.outstanding, icon: Icons.account_balance_wallet_outlined, tone: Tone.warning, caption: '${s.activePlans} active plans'),
          ),
        ],
      ),
    );
  }
}

class _DueList extends ConsumerWidget {
  const _DueList({required this.scope});

  final DueScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final canCollect = ref.watch(currentUserProvider).can(Perm.installmentsCollect);
    final value = ref.watch(installmentDuesProvider((scope: scope, customerId: null)));
    return AsyncBody<List<InstallmentDue>>(
      value: value,
      onRetry: () => ref.invalidate(installmentDuesProvider),
      builder: (items) {
        final total = items.fold<double>(0, (s, i) => s + i.remaining);
        if (items.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: const [
              _SummaryStrip(),
              SizedBox(height: 24),
              EmptyState(icon: Icons.event_available_rounded, title: 'Nothing here', message: 'No unpaid installments in this period.'),
            ],
          );
        }
        return AdaptiveList(
          rowHeight: 84,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SummaryStrip(),
              const SizedBox(height: 4),
              Text('${items.length} installments  |  ${Fmt.money(total)}', style: context.text.labelLarge?.copyWith(color: c.textMuted, fontWeight: FontWeight.w700)),
            ],
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final d = items[i];
            final tone = d.isOverdue ? Tone.danger : (d.dueDate.difference(DateTime.now()).inDays <= 0 ? Tone.warning : Tone.info);
            final when = d.isOverdue ? '${d.daysOverdue} day(s) overdue' : (_isToday(d.dueDate) ? 'Due today' : 'Due ${Fmt.date(d.dueDate)}');
            return AppCard(
              onTap: () => context.push('/installments/${d.planId}'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  IconBadge(d.isOverdue ? Icons.warning_amber_rounded : Icons.event_rounded, tone: tone, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        Text('${d.planNo}  |  installment ${d.seq}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                        Text(when, style: context.text.bodySmall?.copyWith(color: d.isOverdue ? c.danger : c.textMuted, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MoneyText(d.remaining, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      if (canCollect)
                        InkWell(
                          onTap: () => _collect(context, ref, d),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Collect', style: TextStyle(color: c.primary, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  Future<void> _collect(BuildContext context, WidgetRef ref, InstallmentDue d) async {
    final res = await showCollectInstallment(context, planId: d.planId, suggested: d.remaining, itemId: d.itemId);
    if (res != null && context.mounted) {
      showToast(context, 'Received. Receipt ${res['receipt_no']}');
    }
  }
}

class _PlansList extends ConsumerStatefulWidget {
  const _PlansList();

  @override
  ConsumerState<_PlansList> createState() => _PlansListState();
}

class _PlansListState extends ConsumerState<_PlansList> {
  String _status = 'active';
  String _search = '';
  int _limit = 50;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(installmentPlansProvider((status: _status, search: _search, customerId: null, limit: _limit)));
    const statuses = [('active', 'Active'), ('overdue', 'Overdue'), ('completed', 'Completed'), ('cancelled', 'Cancelled'), ('all', 'All')];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SearchField(hint: 'Search plan, customer or phone', onChanged: (v) => setState(() => _search = v.trim())),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              for (final s in statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) => setState(() => _status = s.$1)),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody<List<InstallmentPlanRow>>(
            value: value,
            onRetry: () => ref.invalidate(installmentPlansProvider),
            builder: (plans) {
              if (plans.isEmpty) {
                return const EmptyState(
                  icon: Icons.event_repeat_rounded,
                  title: 'No installment plans',
                  message: 'Sell on installment from the POS checkout: choose Installment and set up the plan.',
                );
              }
              return AdaptiveList(
                rowHeight: 96,
                itemCount: plans.length,
                footer: plans.length >= _limit ? LoadMoreFooter(onPressed: () => setState(() => _limit += 50)) : null,
                itemBuilder: (_, i) {
                  return PlanSummaryCard(plan: plans[i]);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
