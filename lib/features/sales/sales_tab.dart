import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/date_range_bar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'sales_data.dart';

class SalesTab extends ConsumerStatefulWidget {
  const SalesTab({super.key});

  @override
  ConsumerState<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends ConsumerState<SalesTab> {
  DateRange _range = DateRange.of(RangePreset.today);
  String _status = 'all';
  String _q = '';
  int _limit = AppConfig.listPageSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = ref.watch(salesListProvider((range: _range, search: _q, customerId: null, status: _status, limit: _limit)));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchField(hint: 'Search invoice number', onChanged: (v) => setState(() => _q = v)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DateRangeBar(value: _range, onChanged: (r) => setState(() { _range = r; _limit = AppConfig.listPageSize; })),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(
            children: [
              for (final f in const [('all', 'All'), ('due', 'With due'), ('void', 'Void')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(f.$2), selected: _status == f.$1, onSelected: (_) => setState(() => _status = f.$1)),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody<List<SaleRow>>(
            value: value,
            onRetry: () => ref.invalidate(salesListProvider),
            builder: (items) {
              if (items.isEmpty) {
                return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No sales found', message: 'Try another date range or filter.');
              }
              final total = items.where((s) => !s.isVoid).fold<double>(0, (a, s) => a + s.total);
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(salesListProvider),
                child: AdaptiveList(
                  rowHeight: 80,
                  itemCount: items.length,
                  header: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${items.length} invoices  |  ${Fmt.money(total)}', style: context.text.labelLarge?.copyWith(color: c.textMuted, fontWeight: FontWeight.w700)),
                  ),
                  footer: items.length >= _limit ? LoadMoreFooter(onPressed: () => setState(() => _limit += AppConfig.listPageSize)) : null,
                  itemBuilder: (_, i) {
                    final s = items[i];
                    return AppCard(
                      onTap: () => context.push('/sales/${s.id}'),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          IconBadge(s.isVoid ? Icons.block_rounded : Icons.receipt_long_rounded, tone: s.isVoid ? Tone.neutral : Tone.brand, size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.invoiceNo, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text('${s.customerName ?? 'Walk-in'}  |  ${Fmt.dateTime(s.date)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              MoneyText(s.total, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, decoration: s.isVoid ? TextDecoration.lineThrough : null)),
                              const SizedBox(height: 4),
                              if (s.isVoid)
                                const StatusPill('Void', dense: true)
                              else if (s.due > 0.004)
                                StatusPill('Due ${Fmt.money(s.due)}', tone: Tone.danger, dense: true)
                              else if (s.returned > 0)
                                const StatusPill('Returned', tone: Tone.warning, dense: true)
                              else
                                const StatusPill('Paid', tone: Tone.success, dense: true),
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
