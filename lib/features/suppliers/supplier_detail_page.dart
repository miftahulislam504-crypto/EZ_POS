import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/attachments_section.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../customers/customers_data.dart';
import '../customers/party_widgets.dart';
import 'suppliers_data.dart';

class SupplierDetailPage extends ConsumerWidget {
  const SupplierDetailPage({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final value = ref.watch(supplierProvider(supplierId));
    final summary = ref.watch(supplierSummaryProvider(supplierId));

    return value.when(
      loading: () => Scaffold(appBar: AppBar(), body: const ListSkeleton(rows: 4)),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorState(message: '$e', onRetry: () => ref.invalidate(supplierProvider))),
      data: (s) {
        if (s == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off_rounded, title: 'Supplier not found'));
        final sum = summary.valueOrNull;
        return DefaultTabController(
          length: 3,
          child: PageScaffold(
            title: s.name,
            subtitle: s.code,
            maxWidth: 900,
            actions: [
              if (user.can(Perm.suppliersManage))
                IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: () => context.push('/suppliers/${s.id}/edit')),
            ],
            bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Ledger'), Tab(text: 'Unpaid bills'), Tab(text: 'Details')]),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Avatar(s.name, size: 52),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.contactPerson ?? s.phone ?? 'No contact', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                  if (s.contactPerson != null && s.phone != null) Text(s.phone!, style: context.text.bodySmall?.copyWith(color: context.colors.textMuted)),
                                ],
                              ),
                            ),
                            BalanceLabel(s.balance, kind: PartyKind.supplier, large: true),
                          ],
                        ),
                        if (sum != null) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _stat(context, 'Total purchase', Fmt.money(sum.totalPurchase)),
                              _stat(context, 'Total paid', Fmt.money(sum.totalPaid)),
                              _stat(context, 'Last purchase', Fmt.date(sum.lastPurchase)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (user.can(Perm.suppliersPayment))
                              Expanded(
                                child: AppButton('Make payment', icon: Icons.payments_outlined, dense: true, onPressed: () async {
                                  await showPartyPaymentSheet(
                                    context, ref,
                                    kind: PartyKind.supplier,
                                    partyId: s.id,
                                    partyName: s.name,
                                    partyPhone: s.phone,
                                    balance: s.balance,
                                    openItems: sum?.openItems ?? const [],
                                  );
                                }),
                              ),
                            if (user.can(Perm.suppliersPayment) && user.can(Perm.purchasesCreate)) const SizedBox(width: 10),
                            if (user.can(Perm.purchasesCreate))
                              Expanded(
                                child: AppButton('New purchase', icon: Icons.add_shopping_cart_rounded, dense: true, kind: ButtonKind.secondary,
                                    onPressed: () => context.push('/purchases/new?supplier=${s.id}')),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      AsyncBody<List<LedgerEntry>>(
                        value: ref.watch(supplierLedgerProvider(s.id)),
                        onRetry: () => ref.invalidate(supplierLedgerProvider),
                        builder: (entries) => LedgerList(entries: entries, kind: PartyKind.supplier),
                      ),
                      _unpaid(context, sum),
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        children: [
                          AppCard(
                            child: Column(
                              children: [
                                InfoRow('Contact person', s.contactPerson ?? '-'),
                                InfoRow('Mobile', s.phone ?? '-'),
                                InfoRow('Alternative', s.altPhone ?? '-'),
                                InfoRow('Email', s.email ?? '-'),
                                InfoRow('Address', s.address ?? '-'),
                                InfoRow('Business type', s.businessType ?? '-'),
                                InfoRow('Notes', s.notes ?? '-'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          AttachmentsSection(
                            entityType: 'supplier',
                            entityId: s.id,
                            title: 'Documents',
                            subtitle: 'Bills, trade licence or agreements',
                            canEdit: user.can(Perm.suppliersManage),
                            canDelete: user.can(Perm.suppliersManage),
                          ),
                        ],
                      ),
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

  Widget _stat(BuildContext context, String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.text.labelSmall?.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          ],
        ),
      );

  Widget _unpaid(BuildContext context, PartySummary? sum) {
    final open = sum?.openItems ?? const <OpenItem>[];
    if (open.isEmpty) return const EmptyState(icon: Icons.task_alt_rounded, title: 'No unpaid bills', message: 'Every purchase from this supplier is paid.');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        const SectionHeader('Payable by age'),
        AgingStrip(open),
        const SizedBox(height: 16),
        for (final o in open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: () => context.push('/purchases/${o.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.number, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        Text('${Fmt.date(o.date)}  |  ${o.ageDays} days', style: context.text.bodySmall?.copyWith(color: context.colors.textMuted)),
                      ],
                    ),
                  ),
                  StatusPill('Due ${Fmt.money(o.due)}', tone: Tone.danger, dense: true),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
