import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/surfaces.dart';
import 'installments_data.dart';

/// One installment plan as a card: customer, progress, paid and what is left. Opens the plan.
class PlanSummaryCard extends StatelessWidget {
  const PlanSummaryCard({super.key, required this.plan, this.showCustomer = true});

  final InstallmentPlanRow plan;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = plan;
    final progress = p.totalPayable <= 0 ? 0.0 : (p.paid / p.totalPayable).clamp(0.0, 1.0);
    return AppCard(
      onTap: () => context.push('/installments/${p.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(showCustomer ? p.customerName : p.planNo,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (p.isActive && p.isOverdue)
                StatusPill('Overdue ${p.overdueDays}d', tone: Tone.danger)
              else
                StatusPill(p.status[0].toUpperCase() + p.status.substring(1),
                    tone: p.status == 'completed' ? Tone.success : (p.status == 'cancelled' ? Tone.neutral : Tone.info)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${showCustomer ? '${p.planNo}  |  ' : ''}${p.invoiceNo}${p.nextDueDate == null ? '' : '  |  next ${Fmt.date(p.nextDueDate)}'}',
            style: context.text.bodySmall?.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: c.surfaceMuted, color: c.primary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Paid ${Fmt.money(p.paid)}', style: context.text.bodySmall?.copyWith(color: c.textMuted, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Left ${Fmt.money(p.outstanding)}', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}
