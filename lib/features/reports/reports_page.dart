import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/date_range_bar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/surfaces.dart';
import '../inventory/inventory_page.dart';
import 'reports_data.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: PageScaffold(
        title: 'Reports',
        bottom: TabBar(isScrollable: true, tabs: [Tab(text: 'Daily sales'), Tab(text: 'Stock valuation')]),
        body: TabBarView(children: [_DailySalesTab(), StockTab()]),
      ),
    );
  }
}

class _DailySalesTab extends ConsumerStatefulWidget {
  const _DailySalesTab();

  @override
  ConsumerState<_DailySalesTab> createState() => _DailySalesTabState();
}

class _DailySalesTabState extends ConsumerState<_DailySalesTab> {
  DateRange _range = DateRange.of(RangePreset.last7);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = ref.watch(dailySalesReportProvider(_range));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
        const SizedBox(height: 14),
        AsyncBody<DailyReport>(
          value: value,
          onRetry: () => ref.invalidate(dailySalesReportProvider),
          loading: const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator())),
          builder: (r) {
            final days = r.rows.where((d) => d.invoices > 0 || d.returns > 0).toList().reversed.toList();
            return LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 900 ? 4 : 2;
                const gap = 12.0;
                final w = (box.maxWidth - gap * (cols - 1)) / cols;
                Widget tile(Widget child) => SizedBox(width: w, child: child);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: gap, runSpacing: gap, children: [
                      tile(StatCard(label: 'Net sales', value: r.netSales, icon: Icons.trending_up_rounded, caption: '${r.invoices} invoices')),
                      tile(StatCard(label: 'Gross profit', value: r.profit, icon: Icons.savings_outlined, tone: Tone.success, caption: 'Revenue less cost of goods')),
                      tile(StatCard(label: 'Collected', value: r.collected, icon: Icons.payments_outlined, tone: Tone.info)),
                      tile(StatCard(label: 'Sold on credit', value: r.creditGiven, icon: Icons.schedule_rounded, tone: Tone.warning)),
                    ]),
                    const SizedBox(height: 16),
                    AppCard(
                      child: Column(
                        children: [
                          InfoRow('Gross sales (with tax)', Fmt.money(r.total)),
                          InfoRow('Discounts given', Fmt.money(r.discount)),
                          InfoRow('VAT / tax collected', Fmt.money(r.tax)),
                          InfoRow('Sales returns', Fmt.money(r.returns)),
                          InfoRow('Cost of goods sold', Fmt.money(r.cogs)),
                        ],
                      ),
                    ),
                    if (r.methods.isNotEmpty) ...[
                      const SectionHeader('Collections by payment method'),
                      AppCard(child: Column(children: [for (final m in r.methods) InfoRow(m.name, Fmt.money(m.amount))])),
                    ],
                    const SectionHeader('Day by day'),
                    if (days.isEmpty)
                      const AppCard(child: Padding(padding: EdgeInsets.all(8), child: Text('No sales in this period.')))
                    else
                      for (final d in days)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(Fmt.day(d.day), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                      Text('${d.invoices} invoices  |  ${Fmt.money(d.returns)} returned', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    MoneyText(d.netSales, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                    Text('Profit ${Fmt.money(d.profit)}', style: context.text.bodySmall?.copyWith(color: c.success, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    const SizedBox(height: 8),
                    Text('Figures follow the rules in docs/ACCOUNTING_RULES.md. Dates use the business time zone (Asia/Dhaka by default).',
                        style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}
