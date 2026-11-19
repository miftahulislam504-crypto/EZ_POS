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
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'purchases_data.dart';

class PurchasesTab extends ConsumerStatefulWidget {
  const PurchasesTab({super.key});

  @override
  ConsumerState<PurchasesTab> createState() => _PurchasesTabState();
}

class _PurchasesTabState extends ConsumerState<PurchasesTab> {
  DateRange _range = DateRange.of(RangePreset.last30);
  String _status = 'all';
  String _q = '';
  int _limit = AppConfig.listPageSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final value = ref.watch(purchasesListProvider((range: _range, search: _q, supplierId: null, status: _status, limit: _limit)));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: user.can(Perm.purchasesCreate)
          ? FloatingActionButton.extended(onPressed: () => context.push('/purchases/new'), icon: const Icon(Icons.add_shopping_cart_rounded), label: const Text('New purchase'))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchField(hint: 'Search purchase or supplier invoice', onChanged: (v) => setState(() => _q = v)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DateRangeBar(value: _range, onChanged: (r) => setState(() { _range = r; _limit = AppConfig.listPageSize; }), presets: const [
              RangePreset.today, RangePreset.last7, RangePreset.last30, RangePreset.thisMonth, RangePreset.custom,
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Row(children: [
              for (final f in const [('all', 'All'), ('due', 'With due')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(f.$2), selected: _status == f.$1, onSelected: (_) => setState(() => _status = f.$1)),
                ),
            ]),
          ),
          Expanded(
            child: AsyncBody<List<PurchaseRow>>(
              value: value,
              onRetry: () => ref.invalidate(purchasesListProvider),
              builder: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: 'No purchases found',
                    message: 'Record stock you buy from suppliers to keep inventory and payables accurate.',
                    actionLabel: user.can(Perm.purchasesCreate) ? 'New purchase' : null,
                    onAction: () => context.push('/purchases/new'),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(purchasesListProvider),
                  child: AdaptiveList(
                    rowHeight: 80,
                    itemCount: items.length,
                    footer: items.length >= _limit ? LoadMoreFooter(onPressed: () => setState(() => _limit += AppConfig.listPageSize)) : null,
                    itemBuilder: (_, i) {
                      final p = items[i];
                      return AppCard(
                        onTap: () => context.push('/purchases/${p.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            const IconBadge(Icons.local_shipping_outlined, tone: Tone.info, size: 42),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.purchaseNo, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text('${p.supplierName ?? 'Supplier'}  |  ${Fmt.date(p.date)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                                ],
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                MoneyText(p.total, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                p.due > 0.004 ? StatusPill('Due ${Fmt.money(p.due)}', tone: Tone.danger, dense: true) : const StatusPill('Paid', tone: Tone.success, dense: true),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
