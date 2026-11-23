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
import 'transfers_data.dart';

Tone transferTone(String status) => switch (status) {
      'requested' => Tone.info,
      'in_transit' => Tone.warning,
      'partially_received' => Tone.warning,
      'received' => Tone.success,
      _ => Tone.neutral,
    };

class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends ConsumerState<TransfersPage> {
  String _status = 'all';
  int _limit = 50;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final value = ref.watch(transfersProvider((status: _status, limit: _limit)));
    const filters = [('all', 'All'), ('requested', 'Requested'), ('in_transit', 'In transit'), ('partially_received', 'Partly received'), ('received', 'Received'), ('cancelled', 'Cancelled')];
    return PageScaffold(
      title: 'Stock transfers',
      actions: [
        if (user.can(Perm.inventoryCount))
          IconButton(tooltip: 'Stock count', icon: const Icon(Icons.fact_check_outlined), onPressed: () => context.push('/inventory/counts')),
      ],
      floatingActionButton: user.can(Perm.transfersManage)
          ? FloatingActionButton.extended(onPressed: () => context.push('/inventory/transfers/new'), icon: const Icon(Icons.add_rounded), label: const Text('New transfer'))
          : null,
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final f in filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(f.$2), selected: _status == f.$1, onSelected: (_) => setState(() => _status = f.$1)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<List<TransferRow>>(
              value: value,
              onRetry: () => ref.invalidate(transfersProvider),
              builder: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.swap_horiz_rounded,
                    title: 'No transfers yet',
                    message: 'Move stock between branches and warehouses. Add a branch first in Settings, Branches.',
                  );
                }
                return AdaptiveList(
                  rowHeight: 92,
                  itemCount: rows.length,
                  footer: rows.length >= _limit ? LoadMoreFooter(onPressed: () => setState(() => _limit += 50)) : null,
                  itemBuilder: (_, i) {
                    final t = rows[i];
                    return AppCard(
                      onTap: () => context.push('/inventory/transfers/${t.id}'),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          const IconBadge(Icons.swap_horiz_rounded, tone: Tone.brand, size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.transferNo, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                Text('${t.fromName}  to  ${t.toName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                                Text(Fmt.dateTime(t.requestedAt), style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                              ],
                            ),
                          ),
                          StatusPill(t.statusLabel, tone: transferTone(t.status)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
