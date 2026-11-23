import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/surfaces.dart';
import '../products/products_tab.dart';
import 'adjust_stock_sheet.dart';
import 'inventory_data.dart';

class InventoryPage extends ConsumerWidget {
  const InventoryPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: PageScaffold(
        title: 'Inventory',
        actions: [
          if (user.can(Perm.transfersView)) IconButton(tooltip: 'Stock transfers', icon: const Icon(Icons.swap_horiz_rounded), onPressed: () => context.push('/inventory/transfers')),
          if (user.can(Perm.inventoryCount)) IconButton(tooltip: 'Stock count', icon: const Icon(Icons.fact_check_outlined), onPressed: () => context.push('/inventory/counts')),
          IconButton(tooltip: 'Serial and IMEI lookup', icon: const Icon(Icons.manage_search_rounded), onPressed: () => context.push('/inventory/serials')),
          IconButton(tooltip: 'Expiry alerts', icon: const Icon(Icons.event_busy_outlined), onPressed: () => context.push('/inventory/expiry')),
        ],
        bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Products'), Tab(text: 'Stock'), Tab(text: 'Movements')]),
        body: const TabBarView(children: [ProductsTab(), StockTab(), MovementsTab()]),
      ),
    );
  }
}

class StockTab extends ConsumerStatefulWidget {
  const StockTab({super.key});

  @override
  ConsumerState<StockTab> createState() => _StockTabState();
}

class _StockTabState extends ConsumerState<StockTab> {
  String _filter = 'all';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final rows = ref.watch(stockReportProvider((filter: _filter, search: _q, limit: 1000)));
    final c = context.colors;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchField(hint: 'Search stock', onChanged: (v) => setState(() => _q = v)),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in const [('all', 'All items'), ('attention', 'Needs attention'), ('low', 'Low stock'), ('out', 'Out of stock')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody<List<StockRow>>(
            value: rows,
            onRetry: () => ref.invalidate(stockReportProvider),
            builder: (items) {
              final total = items.fold<double>(0, (s, r) => s + r.value);
              final low = items.where((r) => r.status == 'low').length;
              final out = items.where((r) => r.status == 'out').length;
              final showSummary = _filter == 'all' && _q.isEmpty && items.isNotEmpty;
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.warehouse_outlined,
                  title: _filter == 'all' ? 'No stock to show' : 'Nothing needs attention',
                  message: _filter == 'all' ? 'Products that track stock appear here.' : 'Every item is above its alert level.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(stockReportProvider),
                child: AdaptiveList(
                  rowHeight: 76,
                  itemCount: items.length,
                  header: showSummary
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              if (user.can(Perm.reportsView))
                                SizedBox(width: 220, child: StatCard(label: 'Stock value', value: total, icon: Icons.account_balance_wallet_outlined)),
                              SizedBox(width: 160, child: StatCard(label: 'Low stock', value: low, icon: Icons.trending_down_rounded, tone: Tone.warning, isMoney: false)),
                              SizedBox(width: 160, child: StatCard(label: 'Out of stock', value: out, icon: Icons.production_quantity_limits_rounded, tone: Tone.danger, isMoney: false)),
                            ],
                          ),
                        )
                      : null,
                  itemBuilder: (_, i) {
                    final r = items[i];
                    final tone = r.status == 'out' ? Tone.danger : (r.status == 'low' ? Tone.warning : Tone.success);
                    return AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      onTap: user.can(Perm.inventoryAdjust)
                          ? () => showAdjustStockSheet(context, ref, productId: r.productId, productName: r.name, unit: r.unit)
                          : null,
                      child: Row(
                        children: [
                          ProductThumb(url: r.imageUrl, size: 46),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text([if (r.sku != null) r.sku!, if (r.damaged > 0) '${Fmt.qty(r.damaged)} damaged'].join('  |  '),
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              StatusPill('${Fmt.qty(r.quantity)} ${r.unit ?? ''}'.trim(), tone: tone),
                              if (user.can(Perm.reportsView))
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(Fmt.money(r.value), style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                                ),
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
    );
  }
}

class MovementsTab extends ConsumerStatefulWidget {
  const MovementsTab({super.key});

  @override
  ConsumerState<MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends ConsumerState<MovementsTab> {
  int _limit = AppConfig.listPageSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = ref.watch(stockMovementsProvider((productId: null, limit: _limit)));
    return AsyncBody<List<StockMovement>>(
      value: value,
      onRetry: () => ref.invalidate(stockMovementsProvider),
      builder: (items) {
        if (items.isEmpty) {
          return const EmptyState(icon: Icons.swap_vert_rounded, title: 'No stock movements yet', message: 'Sales, purchases and adjustments will be listed here.');
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(stockMovementsProvider),
          child: AdaptiveList(
            rowHeight: 74,
            itemCount: items.length,
            footer: items.length >= _limit ? LoadMoreFooter(onPressed: () => setState(() => _limit += AppConfig.listPageSize)) : null,
            itemBuilder: (_, i) {
              final m = items[i];
              final positive = m.quantity > 0;
              return AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    IconBadge(positive ? Icons.south_west_rounded : Icons.north_east_rounded,
                        tone: positive ? Tone.success : Tone.danger, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('${m.typeLabel}${m.bucket != 'quantity' ? ' (${m.bucket})' : ''}  |  ${Fmt.dateTime(m.createdAt)}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                        ],
                      ),
                    ),
                    Text('${positive ? '+' : ''}${Fmt.qty(m.quantity)} ${m.unit ?? ''}'.trim(),
                        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: positive ? c.success : c.danger)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
