import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/date_range_bar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../purchases/purchases_tab.dart';
import '../sales/sales_data.dart';
import '../sales/sales_tab.dart';
import 'payments_data.dart';

class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final tabs = <(String, Widget)>[
      if (user.can(Perm.salesView)) ('Sales', const SalesTab()),
      if (user.can(Perm.purchasesView)) ('Purchases', const PurchasesTab()),
      if (user.canAny([Perm.customersView, Perm.suppliersView])) ('Payments', const PaymentsTab()),
      if (user.can(Perm.salesView)) ('Returns', const ReturnsTab()),
    ];
    if (tabs.isEmpty) {
      return const PageScaffold(
        title: 'Transactions',
        body: EmptyState(icon: Icons.lock_outline_rounded, title: 'No access', message: 'Your role does not include transaction history.'),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: PageScaffold(
        title: 'Transactions',
        bottom: TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t.$1)]),
        body: TabBarView(children: [for (final t in tabs) t.$2]),
      ),
    );
  }
}

class PaymentsTab extends ConsumerStatefulWidget {
  const PaymentsTab({super.key});

  @override
  ConsumerState<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends ConsumerState<PaymentsTab> {
  DateRange _range = DateRange.of(RangePreset.last30);
  bool _customers = true;
  int _limit = AppConfig.listPageSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final canCustomers = user.can(Perm.customersView);
    final canSuppliers = user.can(Perm.suppliersView);
    final showCustomers = canCustomers && (_customers || !canSuppliers);
    final q = (range: _range, limit: _limit);
    final value = ref.watch(showCustomers ? customerPaymentsProvider(q) : supplierPaymentsProvider(q));

    return Column(
      children: [
        if (canCustomers && canSuppliers)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('Received from customers')), ButtonSegment(value: false, label: Text('Paid to suppliers'))],
              selected: {_customers},
              onSelectionChanged: (s) => setState(() => _customers = s.first),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: DateRangeBar(value: _range, onChanged: (r) => setState(() { _range = r; _limit = AppConfig.listPageSize; }), presets: const [
            RangePreset.today, RangePreset.yesterday, RangePreset.last7, RangePreset.last30, RangePreset.thisMonth, RangePreset.custom,
          ]),
        ),
        Expanded(
          child: AsyncBody<List<PaymentRow>>(
            value: value,
            onRetry: () {
              ref.invalidate(customerPaymentsProvider);
              ref.invalidate(supplierPaymentsProvider);
            },
            builder: (items) {
              if (items.isEmpty) {
                return const EmptyState(icon: Icons.payments_outlined, title: 'No payments in this period', message: 'Collections and supplier payments will be listed here.');
              }
              final total = items.fold<double>(0, (s, p) => s + p.amount);
              return AdaptiveList(
                rowHeight: 76,
                itemCount: items.length,
                header: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${items.length} payments  |  ${Fmt.money(total)}', style: context.text.labelLarge?.copyWith(color: c.textMuted, fontWeight: FontWeight.w700)),
                ),
                footer: items.length >= _limit ? LoadMoreFooter(onPressed: () => setState(() => _limit += AppConfig.listPageSize)) : null,
                itemBuilder: (_, i) {
                  final p = items[i];
                  return AppCard(
                    onTap: () => context.push(showCustomers ? '/customers/${p.partyId}' : '/suppliers/${p.partyId}'),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        IconBadge(showCustomers ? Icons.south_west_rounded : Icons.north_east_rounded, tone: showCustomers ? Tone.success : Tone.warning, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.partyName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text('${p.number}  |  ${p.accountName}  |  ${Fmt.dateTime(p.date)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                            ],
                          ),
                        ),
                        MoneyText(p.amount, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: showCustomers ? c.success : c.text)),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class ReturnsTab extends ConsumerStatefulWidget {
  const ReturnsTab({super.key});

  @override
  ConsumerState<ReturnsTab> createState() => _ReturnsTabState();
}

class _ReturnsTabState extends ConsumerState<ReturnsTab> {
  DateRange _range = DateRange.of(RangePreset.last30);
  int _limit = AppConfig.listPageSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = ref.watch(salesReturnsProvider((range: _range, limit: _limit)));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: DateRangeBar(value: _range, onChanged: (r) => setState(() { _range = r; _limit = AppConfig.listPageSize; })),
        ),
        Expanded(
          child: AsyncBody<List<ReturnRow>>(
            value: value,
            onRetry: () => ref.invalidate(salesReturnsProvider),
            builder: (items) {
              if (items.isEmpty) {
                return const EmptyState(icon: Icons.assignment_return_outlined, title: 'No returns in this period', message: 'Open an invoice and choose Return items to record one.');
              }
              return AdaptiveList(
                rowHeight: 80,
                itemCount: items.length,
                footer: items.length >= _limit ? LoadMoreFooter(onPressed: () => setState(() => _limit += AppConfig.listPageSize)) : null,
                itemBuilder: (_, i) {
                  final r = items[i];
                  return AppCard(
                    onTap: () => context.push('/sales/${r.saleId}'),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        const IconBadge(Icons.assignment_return_outlined, tone: Tone.warning, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.returnNo, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text('${r.invoiceNo}  |  ${r.customerName ?? 'Walk-in'}  |  ${Fmt.date(r.date)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            MoneyText(r.total, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            if (r.refund > 0) Text('Refund ${Fmt.money(r.refund)}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
