import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/date_range_bar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/surfaces.dart';
import 'installments_data.dart';

class InstallmentReportPage extends ConsumerStatefulWidget {
  const InstallmentReportPage({super.key});

  @override
  ConsumerState<InstallmentReportPage> createState() => _InstallmentReportPageState();
}

class _InstallmentReportPageState extends ConsumerState<InstallmentReportPage> {
  DateRange _range = DateRange.of(RangePreset.thisMonth);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = ref.watch(installmentReportProvider(_range));
    return PageScaffold(
      title: 'Installment report',
      maxWidth: 980,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          DateRangeBar(
            value: _range,
            onChanged: (r) => setState(() => _range = r),
            presets: const [RangePreset.today, RangePreset.last7, RangePreset.last30, RangePreset.thisMonth, RangePreset.custom],
          ),
          const SizedBox(height: 12),
          AsyncBody<Map<String, dynamic>>(
            value: value,
            onRetry: () => ref.invalidate(installmentReportProvider),
            loading: const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            builder: (r) {
              final sales = asMap(r['sales']);
              final collected = asMap(r['collected']);
              final now = asMap(r['now']);
              final perf = asMap(r['performance']);
              final expected = dbl(perf['expected']);
              final got = dbl(perf['collected']);
              final rate = expected <= 0 ? 0.0 : (got / expected).clamp(0.0, 1.0);
              final onTime = dbl(perf['on_time']);
              final customers = asRows(r['customers']);
              final products = asRows(r['products']);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader('Sold on installment in this period'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _tile(StatCard(label: 'Installment sales', value: dbl(sales['product_total']), icon: Icons.event_repeat_rounded, caption: '${intOf(sales['plans'])} plans')),
                      _tile(StatCard(label: 'Down payments', value: dbl(sales['down_payment']), icon: Icons.south_west_rounded, tone: Tone.success)),
                      _tile(StatCard(label: 'Financed', value: dbl(sales['financed']), icon: Icons.account_balance_outlined, tone: Tone.info)),
                      _tile(StatCard(label: 'Service charge', value: dbl(sales['service_charge']), icon: Icons.percent_rounded, tone: Tone.warning)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('Collections and balances'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _tile(StatCard(label: 'Collected in period', value: dbl(collected['amount']), icon: Icons.payments_outlined, tone: Tone.success, caption: '${intOf(collected['receipts'])} receipts')),
                      _tile(StatCard(label: 'Outstanding now', value: dbl(now['outstanding']), icon: Icons.account_balance_wallet_outlined, tone: Tone.warning, caption: '${intOf(now['active_plans'])} active plans')),
                      _tile(StatCard(label: 'Overdue now', value: dbl(now['overdue_amount']), icon: Icons.warning_amber_rounded, tone: Tone.danger, caption: '${intOf(now['overdue_count'])} installments')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('Collection performance', subtitle: 'Installments that fell due inside the period'),
                  AppCard(
                    child: Column(
                      children: [
                        InfoRow('Expected', Fmt.money(expected)),
                        InfoRow('Collected', Fmt.money(got), valueColor: c.success),
                        InfoRow('Paid on or before the due date', Fmt.money(onTime)),
                        InfoRow('Installments due / fully paid', '${intOf(perf['installments'])} / ${intOf(perf['fully_paid'])}'),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(value: rate, minHeight: 10, backgroundColor: c.surfaceMuted, color: c.primary),
                        ),
                        const SizedBox(height: 6),
                        Align(alignment: Alignment.centerRight, child: Text('${(rate * 100).toStringAsFixed(1)} percent collected', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('Customers with open plans'),
                  if (customers.isEmpty)
                    Text('No open plans.', style: context.text.bodyMedium?.copyWith(color: c.textMuted))
                  else
                    for (final x in customers.take(50))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => context.push('/customers/${x['customer_id']}'),
                        leading: Avatar((x['name'] as String?) ?? '?', size: 38),
                        title: Text((x['name'] as String?) ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${intOf(x['plans'])} plan(s)  |  paid ${Fmt.money(dbl(x['paid']))}${dbl(x['overdue']) > 0 ? '  |  overdue ${Fmt.money(dbl(x['overdue']))}' : ''}'),
                        trailing: Text(Fmt.money(dbl(x['outstanding'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                  const SizedBox(height: 20),
                  const SectionHeader('Products sold on installment'),
                  if (products.isEmpty)
                    Text('No installment sales in this period.', style: context.text.bodyMedium?.copyWith(color: c.textMuted))
                  else
                    for (final x in products.take(50))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text((x['name'] as String?) ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${Fmt.qty(dbl(x['quantity']))} sold'),
                        trailing: Text(Fmt.money(dbl(x['revenue'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tile(Widget w) => SizedBox(width: 220, child: w);
}
