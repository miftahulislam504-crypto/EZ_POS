import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/date_range_bar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/surfaces.dart';
import '../cash/cash_data.dart';
import '../installments/installments_data.dart';
import '../inventory/inventory_data.dart';
import '../sales/sales_data.dart';
import '../transactions/payments_data.dart';
import 'dashboard_data.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int _days = 7;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(salesTrendProvider);
    ref.invalidate(topProductsProvider);
    ref.invalidate(topCategoriesProvider);
    ref.invalidate(lowStockProvider);
    ref.invalidate(salesListProvider);
    ref.invalidate(customerPaymentsProvider);
    ref.invalidate(installmentSummaryProvider);
    ref.invalidate(myShiftProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final summary = ref.watch(dashboardSummaryProvider);
    final wide = Breakpoints.isWide(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Home', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh', onPressed: _refresh),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ResponsiveCenter(
          maxWidth: 1240,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              Text('${_greeting()}, ${user.fullName.split(' ').first}', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 2),
              Text('${user.business.name}  |  ${user.branchName}  |  ${Fmt.day(DateTime.now())}', style: context.text.bodyMedium?.copyWith(color: c.textMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 18),
              _QuickActions(user: user),
              const SizedBox(height: 18),
              AsyncBody<DashboardSummary>(
                value: summary,
                onRetry: () => ref.invalidate(dashboardSummaryProvider),
                loading: const _CardsSkeleton(),
                builder: (s) => _SummaryGrid(summary: s, user: user),
              ),
              if (user.can(Perm.installmentsView) || user.can(Perm.cashView)) ...[
                const SizedBox(height: 22),
                _Phase2Cards(user: user),
              ],
              const SizedBox(height: 22),
              if (user.can(Perm.dashboardView)) ...[
                SectionHeader('Sales trend', trailing: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [ButtonSegment(value: 7, label: Text('7 days')), ButtonSegment(value: 30, label: Text('30 days'))],
                  selected: {_days},
                  onSelectionChanged: (v) => setState(() => _days = v.first),
                )),
                _TrendChart(days: _days),
                const SizedBox(height: 22),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _TopList(title: 'Top products', days: _days, categories: false)),
                      const SizedBox(width: 16),
                      Expanded(child: _TopList(title: 'Top categories', days: _days, categories: true)),
                    ],
                  )
                else ...[
                  _TopList(title: 'Top products', days: _days, categories: false),
                  const SizedBox(height: 16),
                  _TopList(title: 'Top categories', days: _days, categories: true),
                ],
                const SizedBox(height: 22),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (user.can(Perm.inventoryView)) Expanded(child: _LowStock()),
                      if (user.can(Perm.inventoryView) && user.can(Perm.salesView)) const SizedBox(width: 16),
                      if (user.can(Perm.salesView)) Expanded(child: _RecentSales()),
                    ],
                  )
                else ...[
                  if (user.can(Perm.inventoryView)) _LowStock(),
                  if (user.can(Perm.inventoryView)) const SizedBox(height: 16),
                  if (user.can(Perm.salesView)) _RecentSales(),
                ],
                if (user.can(Perm.customersView)) ...[const SizedBox(height: 16), _RecentPayments()],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Installment collection and cash register status.
class _Phase2Cards extends ConsumerWidget {
  const _Phase2Cards({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = <Widget>[];
    if (user.can(Perm.installmentsView)) {
      final s = ref.watch(installmentSummaryProvider).valueOrNull;
      if (s != null) {
        cards.addAll([
          StatCard(label: 'Installments due today', value: s.dueTodayAmount, icon: Icons.event_rounded, tone: Tone.info, caption: '${s.dueTodayCount} to collect', onTap: () => context.go('/installments')),
          StatCard(label: 'Overdue installments', value: s.overdueAmount, icon: Icons.warning_amber_rounded, tone: Tone.danger, caption: '${s.overdueCount} overdue', onTap: () => context.go('/installments')),
          StatCard(label: 'Installments collected today', value: s.collectedToday, icon: Icons.payments_outlined, tone: Tone.success, caption: 'This month ${Fmt.money(s.collectedMonth)}', onTap: () => context.go('/installments')),
        ]);
      }
    }
    if (user.can(Perm.cashView)) {
      final shift = ref.watch(myShiftProvider).valueOrNull;
      cards.add(StatCard(
        label: 'Cash register',
        value: 0,
        isMoney: false,
        icon: Icons.point_of_sale_rounded,
        tone: shift == null ? Tone.neutral : Tone.success,
        caption: shift == null ? 'No open shift. Tap to open one.' : 'Shift ${shift.shiftNo} is open',
        formatter: (_) => shift == null ? 'Closed' : 'Open',
        onTap: () => context.go('/cash'),
      ));
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 1000 ? 4 : (box.maxWidth >= 640 ? 3 : 2);
        const gap = 12.0;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in cards) SizedBox(width: w, child: c)]);
      },
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final actions = <(String, IconData, String, bool)>[
      ('New sale', Icons.point_of_sale_rounded, '/pos', user.can(Perm.salesCreate)),
      ('New purchase', Icons.add_shopping_cart_rounded, '/purchases/new', user.can(Perm.purchasesCreate)),
      ('Add product', Icons.inventory_2_outlined, '/products/new', user.can(Perm.productsManage)),
      ('Add customer', Icons.person_add_alt_1_rounded, '/customers/new', user.can(Perm.customersManage)),
      ('Add supplier', Icons.add_business_outlined, '/suppliers/new', user.can(Perm.suppliersManage)),
      ('Collect due', Icons.payments_outlined, '/customers', user.can(Perm.customersPayment)),
      ('Collect installment', Icons.event_repeat_rounded, '/installments', user.can(Perm.installmentsCollect)),
      ('Stock transfer', Icons.swap_horiz_rounded, '/inventory/transfers', user.can(Perm.transfersView)),
      ('Cash register', Icons.account_balance_wallet_outlined, '/cash', user.can(Perm.cashView)),
      ('Add expense', Icons.receipt_outlined, '/expenses', user.can(Perm.expensesCreate)),
      ('Reports', Icons.bar_chart_rounded, '/reports', user.can(Perm.reportsView)),
    ].where((a) => a.$4).toList();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final a in actions)
          ActionChip(
            avatar: Icon(a.$2, size: 18, color: context.colors.primary),
            label: Text(a.$1),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            onPressed: () => a.$3.contains('/new') ? context.push(a.$3) : context.go(a.$3),
          ),
      ],
    );
  }
}

class _CardsSkeleton extends StatelessWidget {
  const _CardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(
        6,
        (_) => const SizedBox(width: 170, child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(width: 36, height: 36, radius: 12), SizedBox(height: 14), Skeleton(width: 90, height: 12), SizedBox(height: 8), Skeleton(width: 120, height: 22)]))),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary, required this.user});

  final DashboardSummary summary;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final cards = <Widget>[
      StatCard(label: "Today's sales", value: s.sales, icon: Icons.trending_up_rounded, caption: '${s.invoices} invoices${s.returns > 0 ? '  |  ${Fmt.money(s.returns)} returned' : ''}', onTap: () => context.go('/transactions')),
      if (s.canViewProfit) StatCard(label: "Today's gross profit", value: s.profit ?? 0, icon: Icons.savings_outlined, tone: Tone.success, caption: 'Before expenses'),
      StatCard(label: 'Collected today', value: s.collected, icon: Icons.payments_outlined, tone: Tone.info, caption: 'Cash, mobile banking and card'),
      StatCard(label: "Today's purchases", value: s.purchases, icon: Icons.local_shipping_outlined, tone: Tone.warning),
      StatCard(label: "Today's expenses", value: s.expenses, icon: Icons.receipt_long_outlined, tone: Tone.danger, onTap: user.can(Perm.expensesView) ? () => context.go('/expenses') : null),
      StatCard(label: 'Customer due', value: s.customerDue, icon: Icons.account_balance_wallet_outlined, tone: Tone.danger, caption: 'Owed to you', onTap: user.can(Perm.customersView) ? () => context.go('/customers') : null),
      StatCard(label: 'Supplier payable', value: s.supplierPayable, icon: Icons.outbox_rounded, tone: Tone.warning, caption: 'You owe suppliers', onTap: user.can(Perm.suppliersView) ? () => context.go('/suppliers') : null),
      if (s.stockValue != null) StatCard(label: 'Stock value', value: s.stockValue!, icon: Icons.warehouse_outlined, caption: 'At average cost', onTap: () => context.go('/inventory')),
      StatCard(label: 'Products', value: s.products, isMoney: false, icon: Icons.inventory_2_outlined, tone: Tone.neutral, caption: '${s.lowStock} low  |  ${s.outOfStock} out of stock', onTap: () => context.go('/inventory')),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 1000 ? 4 : (box.maxWidth >= 640 ? 3 : 2);
        const gap = 12.0;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in cards) SizedBox(width: w, child: c)]);
      },
    );
  }
}

class _TrendChart extends ConsumerWidget {
  const _TrendChart({required this.days});

  final int days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = ref.watch(salesTrendProvider(days));
    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      child: SizedBox(
        height: 240,
        child: value.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (points) {
            final maxY = points.fold<double>(0, (m, p) => p.sales > m ? p.sales : m);
            if (maxY == 0) {
              return const EmptyState(icon: Icons.show_chart_rounded, title: 'No sales in this period', message: 'Sales will plot here as you make them.');
            }
            final interval = (maxY / 4).ceilToDouble();
            return LineChart(
              LineChartData(
                minY: 0,
                maxY: interval * 4,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (_) => FlLine(color: c.border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      interval: interval,
                      getTitlesWidget: (v, meta) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(Fmt.compactMoney(v), textAlign: TextAlign.end, style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: days == 7 ? 1 : 5,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= points.length) return const SizedBox.shrink();
                        final d = points[i].day;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(days == 7 ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1] : '${d.day}/${d.month}',
                              style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => c.sidebar,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem('${Fmt.date(points[s.x.toInt()].day)}\n', const TextStyle(color: Colors.white70, fontSize: 11), children: [
                          TextSpan(text: Fmt.money(s.y), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        ]),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].sales)],
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: c.primary,
                    barWidth: 3.2,
                    dotData: FlDotData(show: days == 7),
                    belowBarData: BarAreaData(show: true, color: c.primary.withValues(alpha: 0.10)),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
            );
          },
        ),
      ),
    );
  }
}

class _TopList extends ConsumerWidget {
  const _TopList({required this.title, required this.days, required this.categories});

  final String title;
  final int days;
  final bool categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = ref.watch(categories ? topCategoriesProvider(days) : topProductsProvider(days));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, subtitle: 'Last $days days by revenue'),
        AppCard(
          child: value.when(
            loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('$e'),
            data: (items) {
              if (items.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text('Nothing sold yet.', style: TextStyle(color: c.textMuted)));
              final max = items.first.revenue == 0 ? 1 : items.first.revenue;
              return Column(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(items[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                              Text(Fmt.money(items[i].revenue), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(value: items[i].revenue / max, minHeight: 7, backgroundColor: c.surfaceMuted),
                          ),
                          const SizedBox(height: 2),
                          Align(alignment: Alignment.centerLeft, child: Text('${Fmt.qty(items[i].quantity)} sold', style: context.text.bodySmall?.copyWith(color: c.textMuted))),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LowStock extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = ref.watch(lowStockProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Stock alerts', trailing: TextButton(onPressed: () => context.go('/inventory'), child: const Text('View all'))),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: value.when(
            loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('$e'),
            data: (rows) {
              if (rows.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text('All stock levels look healthy.', style: TextStyle(color: c.textMuted)));
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) Divider(color: c.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(rows[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                          StatusPill(rows[i].status == 'out' ? 'Out of stock' : '${Fmt.qty(rows[i].quantity)} left', tone: rows[i].status == 'out' ? Tone.danger : Tone.warning, dense: true),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecentSales extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = ref.watch(salesListProvider((range: DateRange.of(RangePreset.last7), search: '', customerId: null, status: 'completed', limit: 6)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Recent sales', trailing: TextButton(onPressed: () => context.go('/transactions'), child: const Text('View all'))),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: value.when(
            loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('$e'),
            data: (rows) {
              if (rows.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text('No sales in the last 7 days.', style: TextStyle(color: c.textMuted)));
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) Divider(color: c.border),
                    InkWell(
                      onTap: () => context.push('/sales/${rows[i].id}'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(rows[i].invoiceNo, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text('${rows[i].customerName ?? 'Walk-in'}  |  ${Fmt.dateTime(rows[i].date)}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                                ],
                              ),
                            ),
                            MoneyText(rows[i].total, style: const TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecentPayments extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = ref.watch(customerPaymentsProvider((range: DateRange.of(RangePreset.last7), limit: 5)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Recent collections'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: value.when(
            loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('$e'),
            data: (rows) {
              if (rows.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text('No due collections in the last 7 days.', style: TextStyle(color: c.textMuted)));
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) Divider(color: c.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(rows[i].partyName, style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text('${rows[i].number}  |  ${rows[i].accountName}  |  ${Fmt.date(rows[i].date)}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                              ],
                            ),
                          ),
                          MoneyText(rows[i].amount, style: TextStyle(fontWeight: FontWeight.w800, color: c.success)),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
