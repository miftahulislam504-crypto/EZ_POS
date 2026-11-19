import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../pos/pos_controller.dart';
import '../sales/sales_data.dart';
import 'customers_data.dart';
import 'party_widgets.dart';

class CustomerDetailPage extends ConsumerWidget {
  const CustomerDetailPage({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final customer = ref.watch(customerProvider(customerId));
    final summary = ref.watch(customerSummaryProvider(customerId));

    return customer.when(
      loading: () => Scaffold(appBar: AppBar(), body: const ListSkeleton(rows: 4)),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorState(message: '$e', onRetry: () => ref.invalidate(customerProvider))),
      data: (c) {
        if (c == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off_rounded, title: 'Customer not found'));
        return DefaultTabController(
          length: 3,
          child: PageScaffold(
            title: c.name,
            subtitle: c.code,
            maxWidth: 900,
            actions: [
              if (user.can(Perm.customersManage))
                IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: () => context.push('/customers/${c.id}/edit')),
            ],
            bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Ledger'), Tab(text: 'Invoices'), Tab(text: 'Details')]),
            body: Column(
              children: [
                _Header(customer: c, summary: summary),
                Expanded(
                  child: TabBarView(
                    children: [
                      _LedgerTab(customerId: c.id),
                      _InvoicesTab(customerId: c.id, summary: summary),
                      _DetailsTab(customer: c),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.customer, required this.summary});

  final Customer customer;
  final AsyncValue<PartySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final s = summary.valueOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Avatar(customer.name, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer.phone ?? 'No phone', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, children: [
                        StatusPill(customer.groupLabel, tone: Tone.brand, dense: true),
                        if (!customer.isActive) const StatusPill('Inactive', dense: true),
                      ]),
                    ],
                  ),
                ),
                BalanceLabel(customer.balance, large: true),
              ],
            ),
            if (s != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  _Mini('Total purchase', Fmt.money(s.totalPurchase)),
                  _Mini('Total paid', Fmt.money(s.totalPaid)),
                  _Mini('Last purchase', Fmt.date(s.lastPurchase)),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (user.can(Perm.customersPayment))
                  Expanded(
                    child: AppButton('Receive payment', icon: Icons.payments_outlined, dense: true, onPressed: () async {
                      await showPartyPaymentSheet(
                        context, ref,
                        kind: PartyKind.customer,
                        partyId: customer.id,
                        partyName: customer.name,
                        partyPhone: customer.phone,
                        balance: customer.balance,
                        openItems: s?.openItems ?? const [],
                      );
                    }),
                  ),
                if (user.can(Perm.customersPayment) && user.can(Perm.salesCreate)) const SizedBox(width: 10),
                if (user.can(Perm.salesCreate))
                  Expanded(
                    child: AppButton('New sale', icon: Icons.point_of_sale_rounded, dense: true, kind: ButtonKind.secondary, onPressed: () {
                      ref.read(cartProvider.notifier).setCustomer(customer);
                      context.go('/pos');
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelSmall?.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}

class _LedgerTab extends ConsumerWidget {
  const _LedgerTab({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(customerLedgerProvider(customerId));
    return AsyncBody<List<LedgerEntry>>(
      value: value,
      onRetry: () => ref.invalidate(customerLedgerProvider),
      builder: (entries) => LedgerList(entries: entries, kind: PartyKind.customer),
    );
  }
}

class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab({required this.customerId, required this.summary});

  final String customerId;
  final AsyncValue<PartySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sales = ref.watch(salesListProvider((range: null, search: '', customerId: customerId, status: 'all', limit: 100)));
    final open = summary.valueOrNull?.openItems ?? const <OpenItem>[];
    return AsyncBody<List<SaleRow>>(
      value: sales,
      onRetry: () => ref.invalidate(salesListProvider),
      builder: (items) {
        if (items.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No invoices yet');
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (open.isNotEmpty) ...[
              const SectionHeader('Outstanding by age'),
              AgingStrip(open),
              const SizedBox(height: 16),
            ],
            const SectionHeader('All invoices'),
            for (final s in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  onTap: () => context.push('/sales/${s.id}'),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.invoiceNo, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            Text(Fmt.dateTime(s.date), style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(s.total, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          if (s.isVoid)
                            const StatusPill('Void', tone: Tone.neutral, dense: true)
                          else if (s.due > 0.004)
                            StatusPill('Due ${Fmt.money(s.due)}', tone: Tone.danger, dense: true)
                          else
                            const StatusPill('Paid', tone: Tone.success, dense: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DetailsTab extends ConsumerWidget {
  const _DetailsTab({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        AppCard(
          child: Column(
            children: [
              InfoRow('Mobile', customer.phone ?? '-'),
              InfoRow('Alternative', customer.altPhone ?? '-'),
              InfoRow('Email', customer.email ?? '-'),
              InfoRow('Present address', customer.presentAddress ?? '-'),
              InfoRow('Permanent address', customer.permanentAddress ?? '-'),
              InfoRow('Occupation', customer.occupation ?? '-'),
              InfoRow('Date of birth', customer.birthDate == null ? '-' : Fmt.date(customer.birthDate)),
              if (user.can(Perm.customersManage)) InfoRow('NID number', customer.nid ?? '-'),
              InfoRow('Notes', customer.notes ?? '-'),
            ],
          ),
        ),
      ],
    );
  }
}
