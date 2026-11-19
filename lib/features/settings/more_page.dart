import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final c = context.colors;
    final items = <(IconData, String, String, String, bool, Tone)>[
      (Icons.people_alt_outlined, 'Customers', 'Profiles, dues and payments', '/customers', user.can(Perm.customersView), Tone.brand),
      (Icons.local_shipping_outlined, 'Suppliers', 'Payables and purchases', '/suppliers', user.can(Perm.suppliersView), Tone.info),
      (Icons.receipt_long_outlined, 'Expenses', 'Rent, bills, salaries', '/expenses', user.can(Perm.expensesView), Tone.warning),
      (Icons.bar_chart_rounded, 'Reports', 'Sales, profit and stock', '/reports', user.can(Perm.reportsView), Tone.success),
      (Icons.settings_outlined, 'Settings', 'Business, team and printing', '/settings', true, Tone.neutral),
    ].where((i) => i.$5).toList();

    return PageScaffold(
      title: 'More',
      maxWidth: 760,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          AppCard(
            child: Row(
              children: [
                Avatar(user.fullName, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text('${user.roleLabel}  |  ${user.business.name}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: () => context.go(i.$4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    IconBadge(i.$1, tone: i.$6, size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.$2, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text(i.$3, style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.textMuted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
